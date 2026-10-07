/// Hard resource limits: every input file is untrusted.
class Limits {
  static const maxFileBytes = 200 * 1024 * 1024;
  static const maxZipEntries = 5000;
  static const maxEntryBytes = 50 * 1024 * 1024; // per decompressed entry
  static const maxCsvRows = 200000;
  static const maxTextLines = 2000000;
}
