# Setting uop an SFTP server in Google Compute Engine

The goal here is to be able to set up an SFTP server , at least for demo purposes, in Google Compute Engine.

This is not a hardened SFTP solution. Just an illustration of what is possible and how to do it.

Reference: https://stackoverflow.com/a/64143107

## Getting set up

1. Modify the [`env.sh`](./env.sh) file, setting your own project, region, and zone.

2. Run the setup script
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

   The final lines of output of the script will look something like this:
   ```
   OK. You can now SSH into the machine this way:
      export VM_INSTANCE_NAME="sftp-example-instance-u0aptk-20241008-233550"
      export EXTERNAL_IP="35.127.123.44"

      gcloud compute ssh "${VM_INSTANCE_NAME}" --project="${GCP_PROJECT}" --zone="${GCE_VM_ZONE}"
      sftp -oPort=22 testuser@${EXTERNAL_IP}
   ```

## Using it

After the setup completes, you should have a server with an ephemeral externally-accessible IP address. You can then
sftp into that server and drop things into the right directory, and the files will be stored in GCS, and the Pubsub topic gets a notification of that.

```
export EXTERNAL_IP="35.127.123.44"
sftp -oPort=22 testuser@${EXTERNAL_IP}
```

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
have rights to delete.  So if you try to upload a file that already exists in
the bucket, it will fail with a permissions error.


## Automating SFTP upload

In the data sub directory, there is a little helper nodejs script that can
automate the upload of a uniquely named file into the `gcs` directory on the remote server.

This will _put_ the HL7 batch file:

```
cd data
npm install
node ./put-one.js
```

This will _put_ a different HL7 file, with a single message:

```
cd data
npm install
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
TOPIC="projects/$GCP_PROJECT}/topics/sftp-server-example-topic"
INT_SA="integration-runner-1"
INT_SA_FULL=${INT_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"
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
