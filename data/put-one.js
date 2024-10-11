// put-one.js
// ------------------------------------------------------------------
//
// created: Wed Oct  9 14:23:48 2024
// last saved: <2024-October-10 21:22:47>

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
const sftp = new Client();

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
  console.log(`  -P PORT          default is ${defaults.PORT}`);
  console.log(
    `  -f SOURCE_FILE   use the specified file as the source (default is ${defaults.SOURCE_FILE}).`
  );
  console.log(
    `  -x EXTENSION     use the specified extension on the uploaded file (default is ${defaults.EXTENSION}).`
  );
}

function rand(min, max) {
  const delta = max - min + 1;
  return Math.floor(Math.random() * delta) + min;
}

function randomizedDate(seed) {
  const yy = String(2015 + rand(0, 9)),
    mm = ("0" + String(rand(1, 11))).slice(-2),
    dd = ("0" + String(rand(3, 28))).slice(-2);

  return `${yy}${mm}${dd}`;
}

function incrementMonth(seed) {
  const yy = seed.substr(0, 4);
  let dd = seed.substr(6, 2),
    mm = seed.substr(4, 2);

  // increment month
  mm = ("0" + (Number(mm) + 1)).slice(-2);
  // decrement day
  dd = ("0" + (Number(dd) - 2)).slice(-2);
  const hh = ("0" + String(rand(0, 23))).slice(-2),
    ss = ("0" + String(rand(0, 59))).slice(-2);
  return `${yy}${mm}${dd}${hh}${ss}`;
}

function uniqifyFileContents(contents) {
  const replacements = {
    "20220308": randomizedDate("20220308")
  };
  replacements["202204060407"] = incrementMonth(replacements["20220308"]);
  Object.keys(replacements).forEach(
    (seed) =>
      (contents = contents.replace(
        new RegExp(`${seed}`, "g"),
        replacements[seed]
      ))
  );
  return contents;
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
      case "-P":
        expecting = "PORT";
        break;

      default:
        if (!expecting) {
          console.err("Syntax error");
          return usage();
        }
        options[expecting] = expecting == "PORT" ? Number(arg) : arg;
        expecting = null;
        break;
    }
  });

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
    console.log("connecting...");
    await sftp.connect(config);
    console.log("SFTP connection established. Uploading...");
    const newFileName = `copy-${randomString(9)}.${options.EXTENSION}`;

    const contents = await fs.readFile(options.SOURCE_FILE, "utf-8"),
      modifiedContents = uniqifyFileContents(contents);
    //console.log(modifiedContents);
    await fs.writeFile(newFileName, modifiedContents, "utf-8");

    // Upload the file
    await sftp.put(newFileName, `gcs/${newFileName}`);
    console.log(`File ${newFileName} uploaded successfully.`);
    await fs.rm(newFileName);
  } catch (err) {
    console.error("Error:", err);
  } finally {
    sftp.end();
  }
}

main(process.argv.slice(2));
