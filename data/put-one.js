// put-one.js
// ------------------------------------------------------------------
//
// created: Wed Oct  9 14:23:48 2024
// last saved: <2024-October-16 04:44:50>

/* jshint esversion:9, node:true, strict:implied */
/* global process, console, Buffer */

const Client = require("ssh2-sftp-client");
const fs = require("node:fs/promises");
const defaults = {
  SOURCE_FILE: "batch-of-three-messages.hl7",
  EXTENSION: "hl7",
  SFTP_HOST: process.env.EXTERNAL_IP,
  USERNAME: "testuser",
  PASSWORD: "Secret123",
  PORT: 22
      };
const DATES_TO_CHANGE = ['20220208', '202203060407'];
const sftp = new Client();

function randomIntInclusive(min, max) {
  const minCeiled = Math.ceil(min);
  const maxFloored = Math.floor(max);
  return Math.floor(Math.random() * (maxFloored - minCeiled + 1) + minCeiled);
}

function contriveDate() {
  const y = randomIntInclusive(2014, 2023),
        YYYY = String(y),
        m = randomIntInclusive(1, 11),
        MM = ('0'+String(m)).slice(-2),
        d = randomIntInclusive(3, 27),
        DD = ('0'+String(d)).slice(-2);
  return `${YYYY}${MM}${DD}`;
}

function deriveDateAndTime(d) {
  // add one to month and subtract one from day
  const YYYY = d.substr(0,4),
        MM = ('0'+String(Number(d.substr(4,2))+1)).slice(-2),
        DD = ('0'+String(Number(d.substr(6,2)) -1)).slice(-2),
        hour = randomIntInclusive(0, 23),
        hh = ('0'+String(hour)).slice(-2),
        minute = randomIntInclusive(0, 59),
        mm = ('0'+String(minute)).slice(-2);
  return `${YYYY}${MM}${DD}${hh}${mm}`;
}

function randomString(L) {
  L = L || 18;
  let s = "";
  do {
    s += Math.random().toString(36).substring(2, 15);
  } while (s.length < L);
  return s.substring(0, L);
}

function usage(val) {
  console.log(`put-one.js: put one file to the SFTP server`);
  console.log(`usage:`);
  console.log(`  node ./put-one.js [OPTIONS]\n`);
  console.log(`options:`);
  console.log(`  -H SFTP_HOST     default is ${defaults.SFTP_HOST}`);
  console.log(`  -u USERNAME      default is ${defaults.USERNAME}`);
  console.log(`  -p PASSWORD      default is ${defaults.PASSWORD}`);
  console.log(`  -P PORT          default is ${defaults.PORT}`);
  console.log(
    `  -f SOURCE_FILE   use the specified file as the source (default is ${defaults.SOURCE_FILE}).`
  );
  console.log(
    `  -x EXTENSION     use the specified extension on the uploaded file (default is ${defaults.EXTENSION}).`
  );
  console.log(`\n\n`);
  process.exit(val);
}

async function main(args) {
  let expecting = null;
  const options = { ...defaults };
  args.forEach(function (arg, ix) {
    switch (arg) {
      case "-?":
      case "-h":
      case "--help":
        return usage(0);

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
      case "-P":
        expecting = "PORT";
        break;

      default:
        if (!expecting) {
          console.error("Syntax error");
          return usage(1);
        }
        options[expecting] = expecting == "PORT" ? Number(arg) : arg;
        expecting = null;
        break;
    }
  });

  if (!options.SFTP_HOST) {
    console.log("you must specify the host with -H, or export EXTERNAL_IP");
    process.exit(1);
  }
  const config = {
    host: options.SFTP_HOST,
    port: options.PORT,
    username: options.USERNAME,
    password: options.PASSWORD
  };

  try {
    // If the user has passed an extension with a leading dot, remove it.
    if (options.EXTENSION.startsWith(".")) {
      options.EXTENSION = options.EXTENSION.slice(1);
    }

    // Need to modify the file before uploading. the HL7 store
    // does not accept duplicates !
    const newContrivedDate = contriveDate();
    const batchFileContents = (await fs.readFile(options.SOURCE_FILE, 'utf-8'))
      .replace(new RegExp(DATES_TO_CHANGE[0], 'g'), newContrivedDate)
      .replace(new RegExp(DATES_TO_CHANGE[1], 'g'), deriveDateAndTime(newContrivedDate));

    //console.log(batchFileContents);

    const newFileName = `copy-${randomString(9)}.${options.EXTENSION}`,
          fqNewFileName = `/tmp/${newFileName}`;

    await fs.writeFile(fqNewFileName, batchFileContents, 'utf-8');
    console.log(fqNewFileName);

    console.log("connecting...");
    await sftp.connect(config);
    console.log("SFTP connection established. Uploading...");
    //await fs.copyFile(options.SOURCE_FILE, newFileName);
    await sftp.put(fqNewFileName, `gcs/${newFileName}`);
    console.log(`File ${newFileName} uploaded successfully.`);

    await fs.rm(fqNewFileName);
  } catch (err) {
    console.error("Error:", err);
  } finally {
    sftp.end();
  }
}

main(process.argv.slice(2));
