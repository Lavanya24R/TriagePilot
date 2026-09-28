import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();

    final path = join(
      databasePath,
      'triagepilot.db',
    );

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            severity TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  static Future<void> insertAlert({
    required String type,
    required String severity,
    required String message,
  }) async {
    final db = await database;

    await db.insert(
      'pending_alerts',
      {
        'type': type,
        'severity': severity,
        'message': message,
        'created_at': DateTime.now().toIso8601String(),
      },
    );

    print('💾 Alert saved to offline queue');
  }

  static Future<List<Map<String, dynamic>>> getPendingAlerts() async {
    final db = await database;

    return await db.query(
      'pending_alerts',
      orderBy: 'id ASC',
    );
  }

  static Future<void> deleteAlert(int id) async {
    final db = await database;

    await db.delete(
      'pending_alerts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}