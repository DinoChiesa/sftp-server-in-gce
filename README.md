# Setting up an SFTP server in Google Compute Engine

The goal here is to be able to set up an SFTP server in Google Compute Engine,
in about 5 minutes.

The basic steps for doing this with the [Google Cloud
console](https://console.cloud.google.com) (interactive UI) are described
[here](https://stackoverflow.com/a/64143107).  But this repo uses a setup script
that depends on gcloud to perform the necessary steps.


## Disclaimer

This example is not an official Google product, nor is it part of an
official Google product.


## Not Production Ready

This is not a hardened SFTP solution. It works great for demonstrations and
Proof-of-concept work, to show what is possible.

To make it hardened, you would need to set up health monitoring and logging and
alerting. This example sets up a single user in the SFTP system; you would want
to use public/private key pairs probably, and set up provisioning and key
management for that. All of that is outside the scope of this setup script.


## Pre-requisites

The pre-requisites for running this setup script are:

- bash
- [gcloud cli](https://cloud.google.com/sdk/docs/install)
- unix command line tools like grep, tr, head, mktemp

If you use [Google Cloud Shell](https://cloud.google.com/shell/docs), those things are already installed.


## Getting set up

It takes about 5 minutes to set up a working SFTP server in Google Compute
Engine (GCE). Follow these steps. Don't be afraid of the script rubbishing your
GCP project; there is a cleanup script that removes all of the configuration the
setup script creates.


1. Using a text editor, modify the [`env.sh`](./env.sh) file, specifying your own
   project, region, and zone.

2. Source the file, to set the environment variables into your shell.
   ```
   source ./env.sh
   ```

3. Run the setup script
   ```
   ./setup-sftp-server-example.sh
   ```
   This script performs a number of steps, using the gcloud command line tool:
   - create a GCS bucket
   - create a Pubsub topic which gets notifications when a new file gets written to the GCS bucket
   - create a Service Account, and grant permissions on that bucket to the SA
   - create a VM instance, using Debian, that uses that service account as its identity
   - create firewall rules allowing SFTP access into the VM instance
   - install sftp onto that VM instance, create a testuser, and configure sshd to allow that user to login
   - install gcsfuse - a filesystem that can use GCS as backing store - onto that instance. Configure it for use with the GCS Bucket.

   This takes just a few minutes. The final lines of output of the script will look something like this:
   ```
   OK. You can now SSH into the machine this way:
      export VM_INSTANCE_NAME="sftp-example-instance-u0aptk-20241008-233550"
      export EXTERNAL_IP="35.127.123.44"

      gcloud compute ssh "${VM_INSTANCE_NAME}" --project="${GCP_PROJECT}" --zone="${GCE_VM_ZONE}"
      sftp -oPort=22 testuser@${EXTERNAL_IP}
   ```


## Using it

After the setup completes, you should have a server with an ephemeral and
externally-accessible IP address. You can then sftp into that server and drop
things into the right directory, and the files will be stored in GCS; the
Pubsub topic will get a notification of each file written.

```
export EXTERNAL_IP="35.127.123.44"
sftp -oPort=22 testuser@${EXTERNAL_IP}
```

There is a single user provisioned: `testuser`.
The password that the script sets for the user is `Secret123`.

If you get an error message like the following:
```
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
The fingerprint for the ED25519 key sent by the remote host is
SHA256:yPBaiCCn+0H6PZ6YKqLnhK6Vl5O4neUJKdSO7N7gKyo.
Please contact your system administrator.
Add correct host key in /Users/dchiesa/.ssh/known_hosts to get rid of this message.
Offending ECDSA key in /Users/dchiesa/.ssh/known_hosts:50
Host key for 34.168.136.91 has changed and you have requested strict checking.
Host key verification failed.
Connection closed.
```

You need to manually modify your `~/.ssh/known_hosts` file, to remove the entry or entries for the EXTERNAL_IP.


After you successfully sign in, you can then cd into the `gcs` directory, and put files into it:
```
cd gcs
put README.md
exit
```

If you then visit
[https://console.cloud.google.com/storage/browser](https://console.cloud.google.com/storage/browser),
and select your project, you should be able to see the bucket
`sftp-server-example-bucket`, with the objects (files) you have uploaded via
FTP.

The SFTP server has rights to create objects in the GCS bucket, but it does not
have rights to delete.  So an attempt to upload a file that already exists in
the bucket will fail with a permissions error.


## Automating SFTP upload

In the data subdirectory, there is a little helper nodejs script that can
automate the upload of a uniquely named file into the `gcs` directory on the remote server.

To use this, you need
[nodejs](https://nodejs.org/en/learn/getting-started/introduction-to-nodejs) and
[npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)
installed on your machine. If you use [Google Cloud
Shell](https://cloud.google.com/shell/docs), those things are already installed.

You need to install the pre-reqs for the nodejs script:

```
cd data
npm install
```

Then, run the script to _put_ the HL7 batch file into the SFTP server:

```
node ./put-one.js
```

This will _put_ a different HL7 file, one that contains a single message:

```
node ./put-one.js -f single-message-example1.hl7
```

That helper script takes some other options. To see them:
```
node ./put-one.js --help
```

## Complementary things

You might use this script that sets up an SFTP server and a GCS Bucket and a Pubsub topic... as
a building block for more elaborations.

The setup script here doesn't help with those possible elaborations, but you could do it yourself.

One good example: use this as an entry point to an execution in [Google Cloud Application Integration](https://cloud.google.com/application-integration/docs/overview).

To set that up, you need to create a new Integration, that uses a PubSub trigger,
and configure the trigger to be invoked with a specific service account.

That service account must have `pubsub.viewer` role on the topic. To set that up, you can use the following:

```
TOPIC="projects/${GCP_PROJECT}/topics/sftp-server-example-topic"
INT_SA="integration-runner-1"
INT_SA_FULL="${INT_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"
gcloud iam service-accounts create "$INT_SA" --project="$GCP_PROJECT" --quiet
gcloud pubsub topics add-iam-policy-binding ${TOPIC} \
  --member="serviceAccount:${INT_SA_FULL}" --role='roles/pubsub.viewer'
```

After you get the trigger working, your integration can download the file from GCS, and then do whatever it wants to do, with that file.

An example integration that picks up a file, and parses it as an HL7 batch file, is included [here](./complementary-things/example-HL7-parse-batch.json).


## Cleaning up

To remove everything the setup script provisions, runt he cleanup script:
```
./clean-sftp-server-example.sh
```

## License

This material is [Copyright 2024 Google LLC](./NOTICE).
and is licensed under the [Apache 2.0 License](LICENSE). This includes the Java
code as well as the API Proxy configuration.

## Support

This example is open-source software, and is not a supported product.  If you
need assistance, you can try inquiring on [the Google Cloud Community
forum](https://www.GoogleCloudCommunity.com/gc/Google-Cloud/ct-p/google-cloud). There
is no service-level guarantee for responses to inquiries posted to that site.
