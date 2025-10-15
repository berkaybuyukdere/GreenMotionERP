#  Firebase Web App

npm install firebase

// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyDKL5-CYr9UN7PmZQqk3sL_AZg5SdlXF2g",
  authDomain: "greenmotionapp-33413.firebaseapp.com",
  projectId: "greenmotionapp-33413",
  storageBucket: "greenmotionapp-33413.firebasestorage.app",
  messagingSenderId: "831733588823",
  appId: "1:831733588823:web:f14cf8021b5f3991b49412",
  measurementId: "G-PPZXXGSYBZ"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);




 // Firestore Database Rules

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Kullanıcı authentication kontrolü
    function isSignedIn() {
      return request.auth != null;
    }
    
    // Tüm collection'lar için izin
    match /{document=**} {
      allow read, write: if isSignedIn();
    }
  }
}


// Firestore Storage Rules

rules_version = '2';

// Craft rules based on data in your Firestore database
// allow write: if firestore.get(
//    /databases/(default)/documents/users/$(request.auth.uid)).data.isAdmin;
service firebase.storage {
  match /b/{bucket}/o {

    // This rule allows anyone with your Storage bucket reference to view, edit,
    // and delete all data in your Storage bucket. It is useful for getting
    // started, but it is configured to expire after 30 days because it
    // leaves your app open to attackers. At that time, all client
    // requests to your Storage bucket will be denied.
    //
    // Make sure to write security rules for your app before that time, or else
    // all client requests to your Storage bucket will be denied until you Update
    // your rules
    match /{allPaths=**} {
      allow read, write: if request.time < timestamp.date(2025, 11, 11);
    }
  }
}
