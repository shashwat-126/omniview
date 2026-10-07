/// Same Dart surface that OmniView uses from the real plugin, but with no native code.
/// Only used by the lite build (see tool/build_lite.sh). Every call reports "unsupported".
class LibreOfficeKitConverterPlugin {
  static const _msg = 'This lite build of OmniView does not include the Office engine (LibreOffice).';

  Future<void> init() async => throw UnsupportedError(_msg);

  Future<String?> convert({
    required String filePath,
    required String outputFormat,
    required String outputFilePath,
  }) async =>
      throw UnsupportedError(_msg);
}
