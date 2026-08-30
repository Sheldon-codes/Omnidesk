import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'email_page_model.dart';

abstract class EmailAttachmentPicker {
  Future<List<EmailAttachment>> pickDocuments(String draftKey);
  Future<List<EmailAttachment>> pickMedia(String draftKey,
      {required bool camera});
}

final emailAttachmentPickerProvider = Provider<EmailAttachmentPicker>(
  (_) => DeviceEmailAttachmentPicker(),
);

class DeviceEmailAttachmentPicker implements EmailAttachmentPicker {
  DeviceEmailAttachmentPicker({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();
  final ImagePicker _imagePicker;

  @override
  Future<List<EmailAttachment>> pickDocuments(String draftKey) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'txt',
        'csv',
        'zip',
        'mp3',
        'mp4',
        'mov',
        'jpg',
        'jpeg',
        'png',
        'webp',
      ],
    );
    return Future.wait(
      result.where((file) => file.path != null).map(
            (file) async => _persist(
              File(file.path!),
              draftKey: draftKey,
              filename: file.name,
              byteCount: await file.length(),
              mimeType: lookupMimeType(file.name) ?? 'application/octet-stream',
            ),
          ),
    );
  }

  @override
  Future<List<EmailAttachment>> pickMedia(
    String draftKey, {
    required bool camera,
  }) async {
    if (camera) {
      final file = await _imagePicker.pickImage(source: ImageSource.camera);
      if (file == null) return const [];
      return [await _persistXFile(file, draftKey)];
    }
    final files = await _imagePicker.pickMultipleMedia();
    return Future.wait(files.map((file) => _persistXFile(file, draftKey)));
  }

  Future<EmailAttachment> _persistXFile(XFile file, String draftKey) async =>
      _persist(
        File(file.path),
        draftKey: draftKey,
        filename: file.name,
        byteCount: await file.length(),
        mimeType: lookupMimeType(file.name) ?? 'application/octet-stream',
      );

  Future<EmailAttachment> _persist(
    File source, {
    required String draftKey,
    required String filename,
    required int byteCount,
    required String mimeType,
  }) async {
    const maxBytes = 25 * 1024 * 1024;
    final security = byteCount > maxBytes
        ? EmailAttachmentSecurity.blocked
        : EmailAttachmentSecurity.safe;
    final draftDirectory = await _draftDirectory(draftKey);
    final safeName =
        '${DateTime.now().microsecondsSinceEpoch}_${path.basename(filename)}';
    final destination = File(path.join(draftDirectory.path, safeName));
    await source.copy(destination.path);
    return EmailAttachment(
      id: 'attachment-${DateTime.now().microsecondsSinceEpoch}',
      filename: filename,
      mimeType: mimeType,
      byteCount: byteCount,
      localPath: destination.path,
      security: security,
      uploadState: security == EmailAttachmentSecurity.safe
          ? EmailAttachmentUploadState.localReady
          : EmailAttachmentUploadState.failed,
      failureMessage: security == EmailAttachmentSecurity.safe
          ? null
          : 'This file is larger than the current 25 MB limit.',
    );
  }

  Future<Directory> _draftDirectory(String draftKey) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'email_drafts',
        draftKey.hashCode.toUnsigned(32).toString()));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }
}
