# toocoob

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web Profile Image Upload (GitHub via Firebase Functions)

This project supports secure profile image upload for web by routing the upload
through Firebase Functions. The GitHub token stays on the server.

### 1. Install functions dependencies

```bash
cd functions
npm install
```

### 2. Configure GitHub secrets on Firebase

```bash
firebase functions:config:set github.owner="<owner>" github.repo="<repo>" github.branch="main" github.folder="player_profiles" github.token="<github_token>"
```

### 3. Deploy functions

```bash
firebase deploy --only functions
```

### 4. Run Flutter web with function URL

```bash
flutter run -d chrome --dart-define=GITHUB_UPLOAD_FUNCTION_URL=https://us-central1-toocoob.cloudfunctions.net/uploadProfileImage
```

After this, admin screens can pick an image and upload it, and `photoUrl`
is saved to Firestore as a GitHub raw URL.
