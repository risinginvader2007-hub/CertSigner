# CertSigner – how to get your IPA (no Mac needed)

1. Create a free account at github.com (skip if you have one).
2. Click **New repository**, name it `CertSigner`, set it to **Public** (free builds), click **Create**.
3. On the new repo page click **uploading an existing file**.
   Drag in ALL files and folders from this project (project.yml, Sources, .github, README.md).
   Important: the hidden `.github` folder must be included. Click **Commit changes**.
4. Open the **Actions** tab. A run called "Build IPA" starts by itself. Wait ~5 minutes for a green tick.
   (If nothing starts: Actions -> Build IPA -> Run workflow.)
5. Click the finished run, scroll to **Artifacts**, download **CertSigner-ipa**, unzip it.
6. Send `CertSigner.ipa` to your iPhone and open it in FlareStore.

If the run shows a red X, open it, copy the error text and paste it to Claude.
