import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign up with email and password
  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      debugPrint('Starting signup process for: $email');

      // Create user with email and password
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      debugPrint('User created with UID: ${userCredential.user?.uid}');

      if (userCredential.user != null) {
        // Store user data in Firestore
        try {
          debugPrint('Attempting to store user data in Firestore...');
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'uid': userCredential.user!.uid,
            'email': email,
            'name': name,
            'createdAt': FieldValue.serverTimestamp(),
          });

          debugPrint('User data successfully stored in Firestore');
          return true;
        } catch (firestoreError) {
          debugPrint(
              'Warning: User created but Firestore data not saved: $firestoreError');
          // Still return true since the auth account was created
          return true;
        }
      } else {
        print('User creation failed - no user returned');
        return false;
      }
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Exception: ${e.code} - ${e.message}');
      if (e.code == 'email-already-in-use') {
        throw 'This email is already registered. Please use a different email or try logging in.';
      } else if (e.code == 'weak-password') {
        throw 'Password is too weak. Please use a stronger password.';
      } else if (e.code == 'invalid-email') {
        throw 'Invalid email address. Please check your email format.';
      } else {
        throw e.message ?? 'An error occurred during signup';
      }
    } catch (e) {
      print('Error during signup: $e');
      print('Error type: ${e.runtimeType}');
      print('Stack trace: ${StackTrace.current}');
      throw 'Failed to create account. Please try again later.';
    }
  }

  // Sign in with email and password
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    try {
      print('Attempting to sign in: $email');
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Sign in successful for user: ${userCredential.user?.uid}');
      return userCredential.user != null;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Exception during signin: ${e.code} - ${e.message}');
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        throw 'Invalid email or password. Please try again.';
      } else if (e.code == 'user-disabled') {
        throw 'This account has been disabled. Please contact support.';
      } else {
        throw e.message ?? 'Invalid email or password';
      }
    } catch (e) {
      print('Error during signin: $e');
      throw 'Failed to sign in. Please try again later.';
    }
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  // Get user name from Firestore
  Future<String?> getUserName(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data()?['name'] as String?;
    } catch (e) {
      print('Error getting user name: $e');
      return null;
    }
  }
}
