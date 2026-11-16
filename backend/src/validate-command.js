// Define the command fields allowed for each supported device type.
const allowedFields = {
  light: ['on'],
  dimmer: ['on', 'level'],
  blind: ['position'],
  thermostat: ['on', 'mode', 'setpoint'],
};

// Check command fields and values before changing device state.
function validateCommand(device, command) {
  // Find the fields supported by this device type.
  const fields = allowedFields[device.type];

  // Reject unsupported device types.
  if (!fields) {
    throw new Error(`Unsupported device type: ${device.type}`);
  }

  // Check every field included in the command.
  for (const [field, value] of Object.entries(command)) {
    // Reject fields that this device cannot control.
    if (!fields.includes(field)) {
      throw new Error(`Unsupported field for ${device.type}: ${field}`);
    }

    // Require power values to be true or false.
    if (field === 'on' && typeof value !== 'boolean') {
      throw new Error('on must be true or false.');
    }

    // Require brightness and blind position to be numbers from 0 to 100.
    if (
      ['level', 'position'].includes(field) &&
      (
        !Number.isFinite(value) ||
        value < 0 ||
        value > 100
      )
    ) {
      throw new Error(`${field} must be a number between 0 and 100.`);
    }

    // Require thermostat setpoints to be between 16 and 30 degrees Celsius.
    if (
      field === 'setpoint' &&
      (
        !Number.isFinite(value) ||
        value < 16 ||
        value > 30
      )
    ) {
      throw new Error('setpoint must be a number between 16 and 30.');
    }

    // Accept only the thermostat modes present in the supplied database.
    if (field === 'mode' && !['cool', 'auto'].includes(value)) {
      throw new Error('Supported modes are cool and auto.');
    }
  }
}

// Allow the simulator to load this validation function.
module.exports = validateCommand;