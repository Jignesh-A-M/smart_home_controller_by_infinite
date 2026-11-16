// Load the MQTT package.
const mqtt = require('mqtt');

// Load our shared connection settings.
const config = require('./config');

// Create an awaitable delay without blocking Node.js.
const { setTimeout: delay } = require('node:timers/promises');

const validateCommand = require('./validate-command');

// Load the function that generates simulated sensor readings.
const generateSensorState = require('./generate-sensor-state');

// Load the scheduler startup function.
const { startScheduler } = require('./scheduler');

// Connect to the broker and retry every 2 seconds if disconnected.
const client = mqtt.connect(config.mqttUrl, {
  connectTimeout: 10000,
  reconnectPeriod: 2000,
});

// Listen for commands addressed to any device under our prefix.
const commandTopic = `${config.topicPrefix}/device/+/set`;

// Track whether a sensor update cycle is already running.
let sensorsUpdating = false;

// Subscribe whenever the broker connection is established.
client.on('connect', () => {
  console.log('Simulator connected to MQTT.');

  // Ask the broker to deliver messages matching our command topic.
  client.subscribe(commandTopic, (error) => {
    if (error) {
      console.error('Subscription failed:', error.message);
      return;
    }

    console.log('Listening for commands:', commandTopic);
  });
});

// Display each incoming command without changing device state yet.
// Read an incoming command and fetch its target device.
client.on('message', async (topic, payload) => {
  try {
    // Convert the received JSON text into a JavaScript object.
    const incoming = JSON.parse(payload.toString());
    // Echo an optional request ID so the app can confirm its own command safely.
    const commandId = incoming && typeof incoming.commandId === 'string' ? incoming.commandId : null;
    const command = commandId ? incoming.state : incoming;

    // Split the topic into its individual sections.
    const topicParts = topic.split('/');

    // Read the device ID from ia/prefix/device/deviceId/set.
    const deviceId = topicParts[3];

    // Request the device's current data from JSON Server.
    const response = await fetch(
      `${config.restUrl}/devices/${deviceId}`
    );

    // Stop processing if JSON Server returns an unsuccessful status.
    if (!response.ok) {
      throw new Error(`Device request failed: HTTP ${response.status}`);
    }

    // Convert the HTTP response body into a JavaScript object.
    const device = await response.json();

    // Reject commands when the device is offline.
    if (!device.online) {
      throw new Error(`Device is offline: ${device.name}`);
    }

    // List the device types that support user commands.
    const controllableTypes = ['light', 'dimmer', 'blind', 'thermostat'];

    // Reject sensors and device types we do not support.
    if (!controllableTypes.includes(device.type)) {
      throw new Error(`Device does not support commands: ${device.type}`);
    }

    // Require the command to be a non-empty JSON object.
    if (
      command === null ||
      typeof command !== 'object' ||
      Array.isArray(command) ||
      Object.keys(command).length === 0
    ) {
      throw new Error('Command must be a non-empty JSON object.');
    }

    console.log('Device:', device.name);
    console.log('Current state:', device.state);
    console.log('Requested change:', command);

    // Validate all requested fields before processing the command.
    validateCommand(device, command);

    // Pick a random whole-number delay between 200 and 1500 milliseconds.
    const delayMs = 200 + Math.floor(Math.random() * 1301);

    console.log(`Simulating device response delay: ${delayMs} ms`);

    // Wait before applying the requested device change.
    await delay(delayMs);

    // Give each command a 10% chance of simulated failure.
    const shouldFail = Math.random() < 0.1;

    // Temporarily force failure to verify the sender's timeout.
//    const shouldFail = true;

    // Drop failed commands without saving a change or sending a reply.
    if (shouldFail) {
      console.log(`Simulated failure for ${deviceId}: no change and no reply.`);
      return;
    }

    // Merge the requested changes with the device's existing state.
    const updatedState = {
      ...device.state,
      ...command,
    };

    // Save the merged state and update time through JSON Server.
    const updateResponse = await fetch(
      `${config.restUrl}/devices/${deviceId}`,
      {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          state: updatedState,
          lastUpdated: new Date().toISOString(),
        }),
      }
    );

    // Stop processing if JSON Server could not save the update.
    if (!updateResponse.ok) {
      throw new Error(`Device update failed: HTTP ${updateResponse.status}`);
    }

    // Read the saved device returned by JSON Server.
    const updatedDevice = await updateResponse.json();

    console.log('Saved state:', updatedDevice.state);
    console.log('Last updated:', updatedDevice.lastUpdated);

    // Build the state topic for the device that was updated.
    const stateTopic = `${config.topicPrefix}/device/${deviceId}/state`;

    // Convert the saved device state into JSON text.
    const statePayload = JSON.stringify(commandId
      ? { commandId, deviceId, state: updatedDevice.state, lastUpdated: updatedDevice.lastUpdated }
      : updatedDevice.state);

    // Send the saved state through the MQTT broker.
    client.publish(stateTopic, statePayload, (error) => {
      if (error) {
        console.error('State publish failed:', error.message);
        return;
      }

      console.log('State published:', stateTopic);
      console.log('Published state:', statePayload);
    });

  } catch (error) {
    // Report invalid JSON, failed requests, or other processing errors.
    console.error('Cannot process command:', error.message);
  }
});


// Save and publish fresh readings for all online sensors.
async function updateSensors() {
  // Skip overlapping cycles or updates while MQTT is disconnected.
  if (sensorsUpdating || !client.connected) {
    return;
  }

  sensorsUpdating = true;

  try {
    // Fetch the latest devices from JSON Server.
    const response = await fetch(`${config.restUrl}/devices`);

    // Stop this cycle if the device request fails.
    if (!response.ok) {
      throw new Error(`Sensor device request failed: HTTP ${response.status}`);
    }

    // Convert the response into JavaScript device objects.
    const devices = await response.json();

    // Select only online sensor devices.
    const sensors = devices.filter(
      (device) => device.type === 'sensor' && device.online
    );

    // Process each sensor separately.
    for (const sensor of sensors) {
      try {
        // Generate readings using the sensor's existing state fields.
        const state = generateSensorState(sensor.state);

        // Save the reading and its timestamp through JSON Server.
        const updateResponse = await fetch(
          `${config.restUrl}/devices/${sensor.id}`,
          {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              state,
              lastUpdated: new Date().toISOString(),
            }),
          }
        );

        // Do not publish a reading that failed to save.
        if (!updateResponse.ok) {
          throw new Error(`Sensor save failed: HTTP ${updateResponse.status}`);
        }

        // Read the saved sensor returned by JSON Server.
        const updatedSensor = await updateResponse.json();

        // Build this sensor's MQTT state topic.
        const topic = `${config.topicPrefix}/device/${sensor.id}/state`;

        // Publish the saved reading without retaining the message.
        client.publish(
          topic,
          JSON.stringify(updatedSensor.state),
          { retain: false },
          (error) => {
            if (error) {
              console.error(`Sensor publish failed for ${sensor.id}:`, error.message);
              return;
            }

            console.log(`Sensor state sent: ${sensor.id}`, updatedSensor.state);
          }
        );
      } catch (error) {
        // Display the underlying connection error for diagnosis.
        console.dir(error.cause ?? error, { depth: 5 });

        console.error('Sensor cycle failed:', error.message);

        // Report one sensor's failure while allowing other sensors to continue.
        console.error(`Sensor update failed for ${sensor.id}:`, error.message);
      }
    }
  } catch (error) {
    // Report a failure to load or process the device list.
    console.error('Sensor cycle failed:', error.message);
  } finally {
    // Allow the next sensor cycle even if this one failed.
    sensorsUpdating = false;
  }
}

// Start a sensor update cycle every 10 seconds.
const sensorTimer = setInterval(updateSensors, 10000);

// Start schedule checks using the existing MQTT connection.
const stopScheduler = startScheduler(client);

// Report connection errors.
client.on('error', (error) => {
  console.error('MQTT error:', error.message);
});

// Show when the client attempts to reconnect.
client.on('reconnect', () => {
  console.log('Reconnecting to MQTT...');
});

// Stop the sensor timer and disconnect when you press Ctrl+C.
process.on('SIGINT', () => {
  console.log('Stopping simulator...');
  clearInterval(sensorTimer);
  // Stop future schedule checks before disconnecting.
  stopScheduler();
  client.end();
});
