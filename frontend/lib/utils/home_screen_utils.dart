import 'package:flutter/material.dart';

class HomeScreenUtils {
  // Helper method for consistent border radius
  static BorderRadius get borderRadius => BorderRadius.circular(12);

  // Show error snackbar
  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
    );
  }

  // Show success snackbar
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
    );
  }

  // Show warning snackbar
  static void showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
    );
  }

  // Show info snackbar
  static void showInfoSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blue,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
    );
  }

  // Check if error is about disconnected player
  static bool isDisconnectedPlayerError(String errorMessage) {
    return errorMessage.contains('disconnected player') ||
        errorMessage.contains('reconnect feature');
  }

  // Check if error is about game ended
  static bool isGameEndedError(String errorMessage) {
    return errorMessage.contains('Game has ended');
  }
}
