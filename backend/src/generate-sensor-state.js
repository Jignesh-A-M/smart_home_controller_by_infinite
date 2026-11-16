// Generate a simulated reading while preserving existing state fields.
function generateSensorState(state) {
  // Copy the state so we do not modify the original object.
  const nextState = { ...state };

  // Update temperature only when the sensor has a numeric temperature.
  if (Number.isFinite(state.temperature)) {
    // Pick a temperature change between -0.5 and +0.5 degrees.
    const change = Math.random() - 0.5;

    // Keep simulated temperature within our chosen demo range of 15–35°C.
    const temperature = Math.max(
      15,
      Math.min(35, state.temperature + change)
    );

    // Round the reading to one decimal place.
    nextState.temperature = Math.round(temperature * 10) / 10;
  }

  // Update humidity only when the sensor has a numeric humidity.
  if (Number.isFinite(state.humidity)) {
    // Pick a whole-number humidity change from -2 through +2.
    const change = Math.floor(Math.random() * 5) - 2;

    // Keep humidity between 0% and 100%.
    nextState.humidity = Math.max(
      0,
      Math.min(100, state.humidity + change)
    );
  }

  // Generate a motion reading only when the sensor has a boolean motion field.
  if (typeof state.motion === 'boolean') {
    nextState.motion = Math.random() < 0.5;
  }

  // Return the generated sensor state.
  return nextState;
}

// Allow the simulator to load this function.
module.exports = generateSensorState;