/// ARCON To-Do verileri (`arcon_todo_api` yanıtlarıyla birebir alanlar).
class TodoTask {
  TodoTask({
    required this.id,
    required this.title,
    this.description = '',
    this.status = 'todo',
    this.tag = '',
    this.scope = 'personal',
    this.assigneeId,
    this.assigneeName = '',
    this.createdBy = 0,
    this.talkChannelId,
    this.talkChannelName = '',
    this.dueDate,
    this.sortOrder = 0,
    this.commentCount = 0,
    this.createdAt = '',
  });

  factory TodoTask.fromJson(Map<String, dynamic> j) => TodoTask(
    id: (j['id'] as num).toInt(),
    title: '${j['title'] ?? ''}',
    description: '${j['description'] ?? ''}',
    status: '${j['status'] ?? 'todo'}',
    tag: '${j['tag'] ?? ''}',
    scope: '${j['scope'] ?? 'personal'}',
    assigneeId: (j['assignee_id'] as num?)?.toInt(),
    assigneeName: '${j['assignee_name'] ?? ''}',
    createdBy: (j['created_by'] as num?)?.toInt() ?? 0,
    talkChannelId: (j['talk_channel_id'] as num?)?.toInt(),
    talkChannelName: '${j['talk_channel_name'] ?? ''}',
    dueDate: j['due_date'] == null || '${j['due_date']}'.isEmpty
        ? null
        : DateTime.tryParse('${j['due_date']}'),
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
    createdAt: '${j['created_at'] ?? ''}',
  );

  final int id;
  String title;
  String description;
  String status;
  String tag;
  String scope;
  int? assigneeId;
  String assigneeName;
  final int createdBy;
  int? talkChannelId;
  String talkChannelName;
  DateTime? dueDate;
  int sortOrder;
  int commentCount;
  final String createdAt;

  bool get isDone => status == 'done';

  bool get isOverdue {
    final d = dueDate;
    if (d == null || isDone) return false;
    final today = DateTime.now();
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }

  bool get isDueSoon {
    final d = dueDate;
    if (d == null || isDone || isOverdue) return false;
    final today = DateTime.now();
    return d.difference(DateTime(today.year, today.month, today.day)).inDays <=
        1;
  }
}

class TodoPerson {
  const TodoPerson({
    required this.id,
    required this.name,
    this.department = '',
    this.username = '',
  });

  factory TodoPerson.fromJson(Map<String, dynamic> j) => TodoPerson(
    id: (j['id'] as num).toInt(),
    name: '${j['display_name'] ?? j['username'] ?? ''}',
    department: '${j['department'] ?? ''}',
    username: '${j['username'] ?? ''}',
  );

  final int id;
  final String name;
  final String department;
  final String username;
}

class TodoComment {
  const TodoComment({
    required this.id,
    required this.userId,
    required this.name,
    required this.body,
    required this.createdAt,
  });

  factory TodoComment.fromJson(Map<String, dynamic> j) => TodoComment(
    id: (j['id'] as num).toInt(),
    userId: (j['user_id'] as num?)?.toInt() ?? 0,
    name: '${j['display_name'] ?? ''}',
    body: '${j['body'] ?? ''}',
    createdAt: '${j['created_at'] ?? ''}',
  );

  final int id;
  final int userId;
  final String name;
  final String body;
  final String createdAt;
}

class TodoChannel {
  const TodoChannel({required this.id, required this.name});
  factory TodoChannel.fromJson(Map<String, dynamic> j) =>
      TodoChannel(id: (j['id'] as num).toInt(), name: '${j['name'] ?? ''}');
  final int id;
  final String name;
}

class TodoBootstrap {
  const TodoBootstrap({
    required this.meId,
    required this.meName,
    required this.statuses,
    required this.departments,
    required this.tasks,
    required this.people,
    required this.channels,
  });

  final int meId;
  final String meName;

  /// Sıralı: todo, doing, review, done → başlık
  final List<MapEntry<String, String>> statuses;
  final List<String> departments;
  final List<TodoTask> tasks;
  final List<TodoPerson> people;
  final List<TodoChannel> channels;
}
