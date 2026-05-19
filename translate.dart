import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isNotEmpty && args[0] == 'remove' && args.length == 2) {
    remove(args[1]);
  } else {
    process();
  }
}

Future<bool> remove(String name) async {
  var dir = Directory("lib/i18n");
  if (!dir.existsSync()) {
    stdout.writeln('Directory lib/i18n does not exist');
    return false;
  }
  List<dynamic> targetDataList = [];
  for (var file in dir.listSync()) {
    if (!file.path.endsWith(".json")) {
      continue;
    }
    var targetData = jsonDecode(await File(file.path).readAsString());
    if (targetData[name] == null) {
      stdout.writeln(
        'translate.json does not have "$name" key in ${file.path}',
      );
      return false;
    }

    targetData.remove(name);
    targetDataList.add({'file': file.path, 'data': targetData});
  }

  final result = await writeToFile(targetDataList);

  if (!result) {
    stdout.writeln('Failed to write translations to files.');
    return false;
  }

  stdout.writeln('Removed "$name" from "lib/i18n" successfully.');

  return true;
}

Future<bool> process() async {
  File file = File("translate.json");
  var data = jsonDecode(await file.readAsString());
  if (data['name'] == null) {
    stdout.writeln('translate.json is missing "name" field');
    return false;
  }

  stdout.writeln('Adding "${data['name']}" to translations');

  if (data['result'] == null) {
    stdout.writeln('translate.json is missing "result" field');
    return false;
  }
  data['name'] = data['name'].replaceAll(' ', '_');
  var map = Map.from(data['result']);
  var target = Directory("lib/i18n").listSync();
  List<dynamic> targetDataList = [];

  for (var file in target) {
    if (!file.path.endsWith(".json")) {
      continue;
    }
    var targetData = jsonDecode(await File(file.path).readAsString());
    var path = file.path.replaceAll('\\', '/');
    if (targetData[data['name']] != null) {
      stdout.writeln(
        'translate.json already has "${data['name']}" key in $path',
      );
      return false;
    }
    var type = path.split('/').last.split('.').first;

    for (var key in map.keys) {
      if (key != type) {
        continue;
      }
      targetData[data['name']] = map[key];
      targetDataList.add({'file': path, 'data': targetData});
    }
    if (targetDataList.firstWhere(
          (e) => e['file'] == path,
          orElse: () => null,
        ) ==
        null) {
      stdout.writeln(
        'translate.json does not have "${data['name']}" key for ${file.path}',
      );
      return false;
    }
  }

  final result = await writeToFile(targetDataList);

  if (!result) {
    stdout.writeln('Failed to write translations to files.');
    return false;
  }

  stdout.writeln('Translations updated successfully.');

  return true;
}

Future<bool> writeToFile(List<dynamic> list) async {
  final encoder = JsonEncoder.withIndent('    ');

  for (var item in list) {
    var file = File(item['file']);
    await file.writeAsString(encoder.convert(item['data']), flush: true);
  }

  return true;
}
