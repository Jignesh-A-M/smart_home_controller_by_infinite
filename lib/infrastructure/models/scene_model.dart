import '../../domain/entities/home_snapshot.dart';
import 'model.dart';

// Follow the reference project's Model/instance fromJson pattern.
class SceneModel extends Model implements Scene {
  const SceneModel({
    this.id = '',
    this.name = '',
    this.icon = 'home',
    this.favourite = false,
    this.actions = const [],
  });
  @override
  final String id;
  @override
  final String name;
  @override
  final String icon;
  @override
  final bool favourite;
  @override
  final List<SceneAction> actions;

  // Validate definitions before accepting them into the local cache.
  SceneModel fromJson(Map<String, dynamic> json) {
    final id = stringFromJson(json, 'id');
    final name = stringFromJson(json, 'name');
    final icon = stringFromJson(json, 'icon');
    final raw = json['actions'];
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        icon == null ||
        json['favourite'] is! bool ||
        raw is! List ||
        raw.isEmpty) {
      throw const FormatException('Invalid scene definition.');
    }
    final actions = raw.map((value) {
      if (value is! Map ||
          value['deviceId'] is! String ||
          value['state'] is! Map ||
          (value['state'] as Map).isEmpty) {
        throw const FormatException('Invalid scene action.');
      }
      return SceneAction(
        value['deviceId'] as String,
        Map<String, dynamic>.from(value['state'] as Map),
      );
    }).toList();
    if (actions.map((a) => a.deviceId).toSet().length != actions.length) {
      throw const FormatException('Select each device only once.');
    }
    return SceneModel(
      id: id,
      name: name,
      icon: icon,
      favourite: json['favourite'] as bool,
      actions: actions,
    );
  }

  // Preserve partial target states exactly as configured.
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'favourite': favourite,
    'actions': actions
        .map((a) => {'deviceId': a.deviceId, 'state': a.state})
        .toList(),
  };
}
