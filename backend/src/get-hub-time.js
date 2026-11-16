// Load the hub's timezone setting.
const config = require('./config');

// Format dates into separate clock fields using the hub's timezone.
const formatter = new Intl.DateTimeFormat('en-GB', {
  timeZone: config.hubTimezone,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  weekday: 'short',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

// Return the date, weekday, and time used for schedule matching.
function getHubTime(date = new Date()) {
  // Split the formatted date into named parts.
  const formattedParts = formatter.formatToParts(date);

  // Convert the parts into an object for easy field access.
  const parts = Object.fromEntries(
    formattedParts.map((part) => [part.type, part.value])
  );

  // Return values matching our schedule's day and time formats.
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    day: parts.weekday.toLowerCase(),
    time: `${parts.hour}:${parts.minute}`,
  };
}

// Allow the scheduler to load this clock function.
module.exports = getHubTime;