/// In-memory only: a browser refresh starts an empty table list at number 1.
/// Saved game progress is stored separately and is never cleared here.
class TableSession {
  final String runId = DateTime.now().microsecondsSinceEpoch.toString();
  static final current = TableSession();
  final Set<String> _tables = {};
  int _nextNumber = 1;

  int reserveNumber() => _nextNumber++;
  void register(String id) => _tables.add(id);
  bool contains(String id) => _tables.contains(id);

  bool isPreviousRun(Map<String, dynamic> table, String tabId, String ownerId) =>
      table['status'] == 'active' &&
      table['ownerUserId'] == ownerId &&
      table['browserTabId'] == tabId &&
      table['browserRunId'] is String && table['browserRunId'] != runId;
}
