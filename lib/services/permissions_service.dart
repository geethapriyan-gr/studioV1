import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Service for handling app permissions
class PermissionsService {
  static final PermissionsService _instance = PermissionsService._internal();
  factory PermissionsService() => _instance;
  PermissionsService._internal();

  /// Check if storage permission is granted
  Future<bool> hasStoragePermission() async {
    if (Platform.isAndroid) {
      // For Android 13+ (API 33+), check for media permissions instead of storage
      final storageStatus = await Permission.storage.status;
      final photosStatus = await Permission.photos.status;
      final videosStatus = await Permission.videos.status;
      
      // Return true if any of the relevant permissions are granted
      return storageStatus.isGranted || photosStatus.isGranted || videosStatus.isGranted;
    } else if (Platform.isIOS) {
      final status = await Permission.photos.status;
      // Accept full or limited access on iOS 14+
      return status.isGranted || status.isLimited;
    }
    return true; // Desktop platforms don't need explicit permission
  }

  /// Request storage permission
  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // For Android 13+ (API 33+), request media permissions
      final List<Permission> permissions = [
        Permission.storage,
        Permission.photos,
        Permission.videos,
      ];
      
      final Map<Permission, PermissionStatus> statuses = await permissions.request();
      
      // Return true if any of the relevant permissions are granted
      return statuses.values.any((status) => status.isGranted);
    } else if (Platform.isIOS) {
      final status = await Permission.photos.request();
      // Accept full or limited access
      return status.isGranted || status.isLimited;
    }
    return true; // Desktop platforms don't need explicit permission
  }

  /// Check if camera permission is granted
  Future<bool> hasCameraPermission() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Request camera permission
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted
  Future<bool> hasMicrophonePermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if media library permission is granted (iOS)
  Future<bool> hasMediaLibraryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.status;
      return status.isGranted;
    }
    return true; // Android doesn't need this specific permission
  }

  /// Request media library permission (iOS)
  Future<bool> requestMediaLibraryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.request();
      return status.isGranted;
    }
    return true; // Android doesn't need this specific permission
  }

  /// Request all necessary permissions for video editing
  Future<Map<String, bool>> requestAllPermissions() async {
    final results = <String, bool>{};

    // Storage/Photos permission
    results['storage'] = await requestStoragePermission();

    // Do NOT proactively request camera/microphone here to avoid extra prompts
    results['camera'] = false;
    results['microphone'] = false;

    // Media library permission (iOS only)
    if (Platform.isIOS) {
      results['mediaLibrary'] = await requestMediaLibraryPermission();
    }

    return results;
  }

  /// Request only the minimal permissions needed at app start
  /// This avoids prompting for camera/microphone until they are actually used.
  Future<Map<String, bool>> requestBasicPermissions() async {
    final results = <String, bool>{};

    // Storage/Photos permission
    results['storage'] = await requestStoragePermission();

    // Do NOT request camera/microphone here. These will be requested on-demand.

    return results;
  }

  /// Check all necessary permissions for video editing
  Future<Map<String, bool>> checkAllPermissions() async {
    final results = <String, bool>{};

    // Storage/Photos permission
    results['storage'] = await hasStoragePermission();

    // We don't require camera/microphone for importing from Photos
    results['camera'] = false;
    results['microphone'] = false;

    // Media library permission (iOS only)
    if (Platform.isIOS) {
      results['mediaLibrary'] = await hasMediaLibraryPermission();
    }

    return results;
  }

  /// Check if all required permissions are granted
  Future<bool> hasAllRequiredPermissions() async {
    final permissions = await checkAllPermissions();
    
    // For basic functionality, we only need storage permissions
    // Camera and microphone can be requested when actually needed
    final storageGranted = permissions['storage'] ?? false;
    
    return storageGranted;
  }

  /// Get permission status message
  String getPermissionStatusMessage(Map<String, bool> permissions) {
    final denied = permissions.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList();

    if (denied.isEmpty) {
      return 'All permissions granted';
    }

    return 'Missing permissions: ${denied.join(', ')}';
  }

  /// Open app settings for manual permission management
  Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }

  /// Check if permission is permanently denied
  Future<bool> isPermissionPermanentlyDenied(Permission permission) async {
    final status = await permission.status;
    return status.isPermanentlyDenied;
  }

  /// Handle permission denial with appropriate action
  Future<bool> handlePermissionDenial(Permission permission) async {
    final isPermanentlyDenied = await isPermissionPermanentlyDenied(permission);
    
    if (isPermanentlyDenied) {
      // Open settings if permanently denied
      await openAppSettings();
      return false;
    } else {
      // Try requesting again
      final status = await permission.request();
      return status.isGranted;
    }
  }

  /// Get user-friendly permission names
  String getPermissionDisplayName(String permissionKey) {
    switch (permissionKey) {
      case 'storage':
        return Platform.isIOS ? 'Photos' : 'Storage';
      case 'camera':
        return 'Camera';
      case 'microphone':
        return 'Microphone';
      case 'mediaLibrary':
        return 'Media Library';
      default:
        return permissionKey;
    }
  }

  /// Check if we need to show rationale for permission
  Future<bool> shouldShowRequestPermissionRationale(Permission permission) async {
    if (Platform.isAndroid) {
      return await permission.shouldShowRequestRationale;
    }
    return false; // iOS doesn't have this concept
  }
}
