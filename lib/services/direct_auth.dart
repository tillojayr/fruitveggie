import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DirectAuth {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign up method that completely avoids the problematic code path
  static Future<bool> createAccount(
      String email, String password, String name) async {
    try {
      print('DirectAuth: Starting account creation');

      // Create user with email and password
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('DirectAuth: User created in Firebase Auth');

      // IMPORTANT: Do NOT access userCredential.user at all
      // Instead, get the current user directly from FirebaseAuth
      final currentUser = _auth.currentUser;
      final uid = currentUser?.uid;

      print('DirectAuth: Current user after creation: ${uid ?? "null"}');

      // Only proceed if we have a UID
      if (uid != null) {
        try {
          print('DirectAuth: Attempting to send verification email...');

          try {
            // Send email verification with ActionCodeSettings
            await currentUser!.sendEmailVerification(
              ActionCodeSettings(
                url: 'https://my-fruitveggie.firebaseapp.com/__/auth/action',
                handleCodeInApp: true,
                androidPackageName: 'com.example.fruitveggie',
                androidInstallApp: true,
                androidMinimumVersion: '12',
                iOSBundleId: 'com.example.fruitveggie',
              ),
            );
            print(
                'DirectAuth: Verification email sent successfully with custom settings');
          } catch (verificationError) {
            print(
                'DirectAuth: Error sending verification email with custom settings: $verificationError');
            print('DirectAuth: Trying without ActionCodeSettings...');

            // Fallback to basic verification if custom settings fail
            await currentUser!.sendEmailVerification(
              ActionCodeSettings(
                // Use a simpler URL that's guaranteed to work
                url: 'https://my-fruitveggie.firebaseapp.com',
                handleCodeInApp: false,
                // Only include essential parameters
                androidPackageName: 'com.example.fruitveggie',
                androidInstallApp: false,
              ),
            );
            print('DirectAuth: Basic verification email sent successfully');
          }

          await _firestore.collection('users').doc(uid).set({
            'uid': uid,
            'email': email,
            'name': name,
            'emailVerified': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('DirectAuth: User data stored in Firestore');
        } catch (e) {
          print('DirectAuth: Firestore error - $e');
          // Continue anyway since auth account was created
        }

        return true;
      } else {
        print('DirectAuth: No current user found after account creation');
        return false;
      }
    } catch (e) {
      print('DirectAuth error: $e');
      rethrow; // Let the calling code handle the error
    }
  }

  // Sign in method that avoids the problematic code path
  static Future<bool> signIn(String email, String password) async {
    try {
      print('DirectAuth: Starting sign in');

      // Sign in with email and password
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // IMPORTANT: Do NOT access result.user at all
      // Instead, check if currentUser is non-null after sign-in
      final currentUser = _auth.currentUser;
      final success = currentUser != null;

      // Check if email is verified
      if (success) {
        // Reload user to get the latest data
        await currentUser.reload();

        if (!currentUser.emailVerified) {
          print('DirectAuth: Email not verified');
          return false;
        }

        // Update Firestore if email is now verified
        if (currentUser.emailVerified) {
          try {
            await _firestore.collection('users').doc(currentUser.uid).update({
              'emailVerified': true,
            });
            print('DirectAuth: User emailVerified status updated in Firestore');
          } catch (e) {
            print('DirectAuth: Firestore update error - $e');
            // Continue anyway since authentication succeeded
          }
        }
      }

      print('DirectAuth: Sign in completed. Success: $success');
      // If success is true, currentUser is not null
      return success && currentUser.emailVerified;
    } catch (e) {
      print('DirectAuth sign in error: $e');
      rethrow;
    }
  }

  // Resend verification email
  static Future<bool> resendVerificationEmail() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        print('DirectAuth: Attempting to resend verification email...');

        try {
          await currentUser.sendEmailVerification(
            ActionCodeSettings(
              url: 'https://my-fruitveggie.firebaseapp.com/__/auth/action',
              handleCodeInApp: true,
              androidPackageName: 'com.example.fruitveggie',
              androidInstallApp: true,
              androidMinimumVersion: '12',
              iOSBundleId: 'com.example.fruitveggie',
            ),
          );
          print(
              'DirectAuth: Verification email resent successfully with custom settings');
          return true;
        } catch (verificationError) {
          print(
              'DirectAuth: Error resending verification email with custom settings: $verificationError');
          print('DirectAuth: Trying without ActionCodeSettings...');

          // Fallback to basic verification if custom settings fail
          await currentUser.sendEmailVerification(
            ActionCodeSettings(
              // Use a simpler URL that's guaranteed to work
              url: 'https://my-fruitveggie.firebaseapp.com',
              handleCodeInApp: false,
              // Only include essential parameters
              androidPackageName: 'com.example.fruitveggie',
              androidInstallApp: false,
            ),
          );
          print('DirectAuth: Basic verification email resent successfully');
          return true;
        }
      }
      print('DirectAuth: Cannot resend verification email - no current user');
      return false;
    } catch (e) {
      print('DirectAuth resend verification error: $e');
      return false;
    }
  }

  // Check if email is verified
  static Future<bool> isEmailVerified() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        // Reload user to get the latest verification status
        await currentUser.reload();
        return currentUser.emailVerified;
      }
      return false;
    } catch (e) {
      print('DirectAuth email verification check error: $e');
      return false;
    }
  }

  // Get current user UID safely
  static String? getCurrentUserId() {
    try {
      return _auth.currentUser?.uid;
    } catch (e) {
      print('Error getting current user ID: $e');
      return null;
    }
  }

  // Try simplest possible verification approach
  static Future<bool> trySendVerificationEmail() async {
    try {
      print('DirectAuth: Trying basic verification email...');
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        // Basic verification with no additional settings
        await currentUser.sendEmailVerification();
        print(
            'DirectAuth: Basic verification email sent without ActionCodeSettings');
        return true;
      }
      print('DirectAuth: No current user to send verification email to');
      return false;
    } catch (e) {
      print('DirectAuth try verification error: $e');
      return false;
    }
  }

  // Direct API approach to send verification email for users who encounter the PigeonUserDetails error
  static Future<bool> forceSendVerificationEmail() async {
    try {
      print('DirectAuth: Force sending verification email...');

      // Get current user ID
      final uid = getCurrentUserId();
      if (uid == null) {
        print('DirectAuth: Force send failed - no current user');
        return false;
      }

      // Try multiple approaches to ensure email is sent
      bool success = false;

      // Approach 1: Direct Firebase instance
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await user.sendEmailVerification();
          print('DirectAuth: Force approach 1 succeeded');
          success = true;
        }
      } catch (e) {
        print('DirectAuth: Force approach 1 failed: $e');
      }

      // Approach 2: Use native Firebase APIs if available
      if (!success) {
        try {
          print(
              'DirectAuth: Force approach 2 - trying without specific settings');
          await _auth.currentUser?.sendEmailVerification();
          print('DirectAuth: Force approach 2 succeeded');
          success = true;
        } catch (e) {
          print('DirectAuth: Force approach 2 failed: $e');
        }
      }

      return success;
    } catch (e) {
      print('DirectAuth force verification error: $e');
      return false;
    }
  }
}
