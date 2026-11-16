// Load Node's built-in file operations.
const fs = require('node:fs');

// Load Node's path utilities.
const path = require('node:path');

// Open a history file that remembers claimed schedule occurrences.
function createScheduleHistory(
  filePath = path.join(__dirname, 'schedule-history.json')
) {
  // Start with empty history when no history file exists.
  let history = {};

  try {
    // Read previously recorded occurrences from disk.
    history = JSON.parse(fs.readFileSync(filePath, 'utf8'));

    // Reject an invalid history structure.
    if (
      history === null ||
      typeof history !== 'object' ||
      Array.isArray(history)
    ) {
      throw new Error('Invalid schedule history.');
    }
  } catch (error) {
    // Allow a missing file, but stop for corrupt data or other file errors.
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }

  // Record an occurrence only when it has not already been claimed.
  function claimOccurrence(key) {
    // Return false when this occurrence was previously recorded.
    if (Object.hasOwn(history, key)) {
      return false;
    }

    // Prepare the updated history without changing the current copy yet.
    const nextHistory = {
      ...history,
      [key]: new Date().toISOString(),
    };

    // Write a temporary file before replacing the saved history.
    fs.writeFileSync(
      `${filePath}.tmp`,
      JSON.stringify(nextHistory, null, 2)
    );

    // Replace the history file with the completed temporary file.
    fs.renameSync(`${filePath}.tmp`, filePath);

    // Update memory only after the file was saved successfully.
    history = nextHistory;

    return true;
  }

  // Expose the function used to claim an occurrence.
  return { claimOccurrence };
}

// Allow other scripts to open schedule history.
module.exports = createScheduleHistory;