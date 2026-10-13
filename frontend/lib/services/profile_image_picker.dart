import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'api_client.dart';

final profileImagePickerProvider = Provider((ref) => ProfileImagePicker());

class ProfileImage {
  final Uint8List bytes;
  final String mimeType, filename;
  const ProfileImage(this.bytes, this.mimeType, this.filename);
}

class ProfileImagePicker {
  Future<ProfileImage?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    if (await file.length() > 5 * 1024 * 1024) {
      throw ApiException(400, 'กรุณาเลือกรูปขนาดไม่เกิน 5 MB');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      return ProfileImage(bytes, 'image/png', 'avatar.png');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return ProfileImage(bytes, 'image/jpeg', 'avatar.jpg');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return ProfileImage(bytes, 'image/webp', 'avatar.webp');
    }
    throw ApiException(400, 'กรุณาเลือกรูป JPG, PNG หรือ WebP');
  }
}
