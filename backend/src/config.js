// Store the connection settings used by our backend scripts.
const config = {
  // JSON Server's address on this computer.
  restUrl: 'http://127.0.0.1:3000',

  // Public MQTT broker address.
  mqttUrl: 'mqtt://broker.hivemq.com:1883',

  // Fixed prefix shared by the simulator and future Flutter app.
  topicPrefix: 'ia/jignesh-08dev808',

  // Interpret schedule times using Indian Standard Time.
  hubTimezone: 'Asia/Kolkata',

};

// Allow other JavaScript files to load these settings using require().
module.exports = config;
