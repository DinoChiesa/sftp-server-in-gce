// put-one.js
// ------------------------------------------------------------------
//
// created: Wed Oct  9 14:23:48 2024
// last saved: <2024-October-09 19:19:55>

/* jshint esversion:9, node:true, strict:implied */
/* global process, console, Buffer */

const Client = require("ssh2-sftp-client");
const defaults = {
  SOURCE_FILE: "batch-of-three-messages.hl7",
  EXTENSION: "hl7",
  SFTP_HOST: process.env.EXTERNAL_IP,
  USERNAME: "testuser",
  PASSWORD: "Secret123"
};
const sftp = new Client();
//const fs = require("node:fs/promises");

function randomString(L) {
  L = L || 18;
  let s = "";
  do {
    s += Math.random().toString(36).substring(2, 15);
  } while (s.length < L);
  return s.substring(0, L);
}

function usage() {
  console.log(`put-one.js: put one file to the SFTP server`);
  console.log(`usage:`);
  console.log(`  node ./put-one.js [OPTIONS]\n`);
  console.log(`options:`);
  console.log(`  -H SFTP_HOST     default is ${defaults.SFTP_HOST}`);
  console.log(`  -u USERNAME      default is ${defaults.USERNAME}`);
  console.log(`  -p PASSWORD      default is ${defaults.PASSWORD}`);
  console.log(
    `  -f SOURCE_FILE   use the specified file as the source (default is ${defaults.SOURCE_FILE}).`
  );
  console.log(
    `  -x EXTENSION     use the specified extension on the uploaded file (default is ${defaults.EXTENSION}).`
  );
}

async function main(args) {
  let expecting = null;
  const options = { ...defaults };
  args.forEach(function (arg, ix) {
    switch (arg) {
      case "-?":
      case "-h":
      case "--help":
        return usage();

      case "-f":
        expecting = "SOURCE_FILE";
        break;
      case "-x":
        expecting = "EXTENSION";
        break;
      case "-H":
        expecting = "SFTP_HOST";
        break;
      case "-u":
        expecting = "USERNAME";
        break;
      case "-p":
        expecting = "PASSWORD";
        break;

      default:
        if (!expecting) {
          console.err("Syntax error");
          return usage();
        }
        options[expecting] = arg;
        expecting = null;
        break;
    }
  });

  const config = {
    host: options.SFTP_HOST,
    port: 22,
    username: options.USERNAME,
    password: options.PASSWORD
  };

  try {
    // If the user has passed an extension with a leading dot, remove it.
    if (options.EXTENSION.startsWith(".")) {
      options.EXTENSION = options.EXTENSION.slice(1);
    }
    console.log("connecting...");
    await sftp.connect(config);
    console.log("SFTP connection established. Uploading...");
    const newFileName = `copy-${randomString(9)}.${options.EXTENSION}`;

    // No need to copy the file only to delete it later.
    // The sftp.put can specify the new name for the target.
    //await fs.copyFile(options.SOURCE_FILE, newFileName);

    // Upload the file
    await sftp.put(options.SOURCE_FILE, `gcs/${newFileName}`);
    console.log(`File ${newFileName} uploaded successfully.`);
    //await fs.rm(newFileName);
  } catch (err) {
    console.error("Error:", err);
  } finally {
    sftp.end();
  }
}

main(process.argv.slice(2));
