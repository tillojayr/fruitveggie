import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createUserData({
    required String uid,
    required String email,
    required String name,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'name': name,
        'mobilePhone': null,
        'profilePicture': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('Successfully stored user data in Firestore');
    } catch (e) {
      print('Error storing user data: $e');
      throw 'Failed to store user data';
    }
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  // Save profile picture in base64 format
  Future<void> saveProfilePicture(String uid, File imageFile) async {
    try {
      // Compress the image before converting to base64
      final Uint8List bytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        throw 'Failed to decode image';
      }

      // Resize the image to a reasonable size (500x500 max while maintaining aspect ratio)
      final int maxDimension = 500;
      img.Image resizedImage = originalImage;

      if (originalImage.width > maxDimension ||
          originalImage.height > maxDimension) {
        if (originalImage.width > originalImage.height) {
          resizedImage = img.copyResize(
            originalImage,
            width: maxDimension,
            height: (originalImage.height * maxDimension / originalImage.width)
                .round(),
          );
        } else {
          resizedImage = img.copyResize(
            originalImage,
            width: (originalImage.width * maxDimension / originalImage.height)
                .round(),
            height: maxDimension,
          );
        }
      }

      // Encode as JPEG with quality 85 for better compression
      final Uint8List compressedBytes =
          Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));

      // Convert to base64
      final String base64Image = base64Encode(compressedBytes);

      // Check if the base64 size is within Firestore's document size limit (1MB)
      if (base64Image.length > 900000) {
        // Keep some margin below 1MB
        throw 'Image is too large for storage. Please select a smaller image.';
      }

      await _firestore.collection('users').doc(uid).update({
        'profilePicture': base64Image,
      });
      print(
          'Successfully stored profile picture. Size: ${(base64Image.length / 1024).round()}KB');
    } catch (e) {
      print('Error storing profile picture: $e');
      throw 'Failed to store profile picture: $e';
    }
  }

  // Get user profile picture as Image widget
  Widget? getProfilePictureWidget(String? base64Image) {
    if (base64Image == null || base64Image.isEmpty) {
      return null;
    }

    try {
      final bytes = base64Decode(base64Image);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
      );
    } catch (e) {
      print('Error decoding profile picture: $e');
      return null;
    }
  }

  // Update user name
  Future<void> updateUserName(String uid, String name) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'name': name,
      });
      print('Successfully updated user name');
    } catch (e) {
      print('Error updating user name: $e');
      throw 'Failed to update user name';
    }
  }

  // Update user mobile phone
  Future<void> updateUserMobilePhone(String uid, String mobilePhone) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'mobilePhone': mobilePhone,
      });
      print('Successfully updated user mobile phone');
    } catch (e) {
      print('Error updating user mobile phone: $e');
      throw 'Failed to update user mobile phone';
    }
  }
}
