// Load the clock used for schedule matching.
const getHubTime = require('./get-hub-time');

// Load the function that selects due schedules.
const findDueSchedules = require('./find-due-schedules');

// Load persistent protection against repeated schedule execution.
const createScheduleHistory = require('./schedule-history');

// Load the shared backend settings.
const config = require('./config');

// Convert a schedule target into a list of device actions.
async function getScheduleActions(schedule) {
  // Read the target stored in the schedule.
  const target = schedule.target;

  // Return one action when the schedule targets a device.
  if (target.type === 'device') {
    return [
      {
        deviceId: target.id,
        state: target.state,
      },
    ];
  }

  // Fetch the scene when the schedule targets a scene.
  if (target.type === 'scene') {
    // Safely include the scene ID in the request URL.
    const sceneId = encodeURIComponent(target.id);

    // Request the scene and limit the HTTP wait to 5 seconds.
    const response = await fetch(
      `${config.restUrl}/scenes/${sceneId}`,
      { signal: AbortSignal.timeout(5000) }
    );

    // Stop if JSON Server cannot return the scene.
    if (!response.ok) {
      throw new Error(`Scene request failed: HTTP ${response.status}`);
    }

    // Convert the HTTP response into a scene object.
    const scene = await response.json();

    // Require the scene to contain a list of actions.
    if (!Array.isArray(scene.actions)) {
      throw new Error('Scene actions must be an array.');
    }

    return scene.actions;
  }

  // Reject target types that our scheduler does not support.
  throw new Error(`Unsupported schedule target: ${target.type}`);
}

// Start checking and dispatching schedules using the simulator's MQTT client.
function startScheduler(client) {
  // Open persistent schedule occurrence history.
  const history = createScheduleHistory();

  // Prevent overlapping checks and work after shutdown.
  let checking = false;
  let stopped = false;

  // Find and dispatch schedules due during the current minute.
  async function checkSchedules() {
    // Skip checks while disconnected, already checking, or stopped.
    if (!client.connected || checking || stopped) {
      return;
    }

    checking = true;

    try {
      // Request the latest schedule definitions.
      const response = await fetch(
        `${config.restUrl}/schedules`,
        { signal: AbortSignal.timeout(5000) }
      );

      // Stop this check if the request fails.
      if (!response.ok) {
        throw new Error(`Schedule request failed: HTTP ${response.status}`);
      }

      // Read the schedule list returned by JSON Server.
      const schedules = await response.json();

      // Reject an unexpected response structure.
      if (!Array.isArray(schedules)) {
        throw new Error('Schedules must be an array.');
      }

      // Read the current date, weekday, and time in the hub timezone.
      const hubTime = getHubTime();

      // Select enabled schedules matching the current day and time.
      const dueSchedules = findDueSchedules(schedules, hubTime);

      // Process each matching schedule separately.
      for (const schedule of dueSchedules) {
        try {
          // Build a unique key for this schedule occurrence.
          const key = `${schedule.id}/${hubTime.date}/${schedule.time}`;

          // Resolve the scene or device target into device actions.
          const actions = await getScheduleActions(schedule);

          // Avoid dispatching if shutdown or disconnection occurred while waiting.
          if (stopped || !client.connected) {
            return;
          }

          // Skip an occurrence already recorded in persistent history.
          if (!history.claimOccurrence(key)) {
            continue;
          }

          console.log('Dispatching schedule:', schedule.name);

          // Send every stored action through the normal device-command topic.
          for (const action of actions) {
            // Build the command topic for this action's device.
            const topic =
              `${config.topicPrefix}/device/${action.deviceId}/set`;

            // Publish the target state without retaining the command.
            client.publish(
              topic,
              JSON.stringify(action.state),
              { qos: 0, retain: false },
              (error) => {
                if (error) {
                  console.error('Schedule publish failed:', error.message);
                  return;
                }

                console.log('Schedule command sent:', action.deviceId);
              }
            );
          }
        } catch (error) {
          // Report one schedule's failure without stopping other schedules.
          console.error(`Schedule failed: ${schedule.name}`, error.message);
        }
      }
    } catch (error) {
      // Report a failed schedule check.
      console.error('Schedule check failed:', error.message);
    } finally {
      // Allow the next check after this one finishes.
      checking = false;
    }
  }


    // Show that the scheduler has started and which timezone it uses.
    console.log('Scheduler started. Timezone:', config.hubTimezone);

    // Check schedules once every second.
    const timer = setInterval(checkSchedules, 1000);

  // Return a function that stops future schedule checks.
  return function stopScheduler() {
    stopped = true;
    clearInterval(timer);
  };
}

// Expose target resolution and scheduler startup.
module.exports = { getScheduleActions, startScheduler };