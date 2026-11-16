// Select schedules that should run at the supplied hub time.
function findDueSchedules(schedules, hubTime) {
  // Return only schedules matching enabled status, time, and weekday.
  return schedules.filter((schedule) => {
    return (
      schedule.enabled === true &&
      schedule.time === hubTime.time &&
      Array.isArray(schedule.days) &&
      schedule.days.includes(hubTime.day)
    );
  });
}

// Allow the scheduler to load this matching function.
module.exports = findDueSchedules;