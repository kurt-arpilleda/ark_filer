import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AutoUpdate {
  static const List<String> apiUrls = [
    "http://192.168.254.163/",
    "http://126.209.7.246/"
  ];

  static const String versionPath = "V4/Others/Kurt/LatestVersionAPK/ArkFiler/version.json";
  static const String apkPathPrefix = "V4/Others/Kurt/LatestVersionAPK/ArkFiler/";

  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  static bool isUpdating = false;

  static Future<void> checkForUpdate(BuildContext context) async {
    // If already updating, don't start another update
    if (isUpdating) {
      return;
    }

    isUpdating = true;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final response = await http.get(Uri.parse("$apiUrl$versionPath")).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final Map<String, dynamic> versionInfo = jsonDecode(response.body);
            final int latestVersionCode = versionInfo["versionCode"];
            final String latestVersionName = versionInfo["versionName"];
            final String releaseNotes = versionInfo["releaseNotes"];
            final String apkFileName = versionInfo["apk"];

            PackageInfo packageInfo = await PackageInfo.fromPlatform();
            int currentVersionCode = int.parse(packageInfo.buildNumber);

            if (latestVersionCode > currentVersionCode) {
              await _showAutomaticUpdateDialog(
                  context,
                  latestVersionName,
                  releaseNotes,
                  apiUrl,
                  apkFileName
              );
              isUpdating = false;
              return;
            } else {
              isUpdating = false;
              return;
            }
          }
        } catch (e) {
          print("Error checking for update from $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        print("Waiting for ${delay.inSeconds} seconds before retrying...");
        await Future.delayed(delay);
      }
    }

    Fluttertoast.showToast(msg: "Failed to check for updates after $maxRetries attempts.");
    isUpdating = false;
  }

  static Future<void> _showAutomaticUpdateDialog(
      BuildContext context,
      String versionName,
      String releaseNotes,
      String apiUrl,
      String apkFileName
      ) async {
    // Enable wakelock when update dialog is shown
    await WakelockPlus.enable();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: Text("Updating Application"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("New Version: $versionName"),
                SizedBox(height: 10),
                Text("Release Notes:"),
                Text(releaseNotes),
                SizedBox(height: 20),
                StreamBuilder<int>(
                  stream: _downloadAndInstallApk(context, apiUrl, apkFileName),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      if (snapshot.data! == 100) {
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              value: 1.0,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                            SizedBox(height: 10),
                            Text("Installation in progress..."),
                          ],
                        );
                      } else if (snapshot.data! == -1) {
                        return Column(
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 40),
                            SizedBox(height: 10),
                            Text("Update failed. Retrying..."),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              value: snapshot.data! / 100,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                            SizedBox(height: 10),
                            Text("${snapshot.data}% Downloaded"),
                          ],
                        );
                      }
                    } else {
                      return Column(
                        children: [
                          LinearProgressIndicator(
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                          SizedBox(height: 10),
                          Text("Preparing download..."),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    // Disable wakelock when dialog is dismissed
    await WakelockPlus.disable();
  }

  static Stream<int> _downloadAndInstallApk(
      BuildContext context,
      String apiUrl,
      String apkFileName
      ) async* {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final String apkFilePath = "${externalDir.path}/$apkFileName";
          final File apkFile = File(apkFilePath);

          final request = http.Request('GET', Uri.parse("$apiUrl$apkPathPrefix$apkFileName"));
          final http.StreamedResponse response = await request.send().timeout(requestTimeout);

          if (response.statusCode == 200) {
            int totalBytes = response.contentLength ?? 0;
            int downloadedBytes = 0;

            yield 0; // Start with 0%

            final fileSink = apkFile.openWrite();
            await for (var chunk in response.stream) {
              downloadedBytes += chunk.length;
              fileSink.add(chunk);
              int progress = ((downloadedBytes / totalBytes) * 100).round();
              yield progress; // Yield the progress percentage
            }
            await fileSink.close();

            if (await apkFile.exists()) {
              yield 100; // Download complete
              await _installApk(context, apkFilePath);
              return;
            } else {
              yield -1;
              Fluttertoast.showToast(msg: "Failed to save the APK file.");
            }
          }
        }
      } catch (e) {
        print("Error downloading APK on attempt $attempt: $e");
        yield -1;
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          print("Waiting for ${delay.inSeconds} seconds before retrying...");
          await Future.delayed(delay);
        }
      }
    }
    Fluttertoast.showToast(msg: "Failed to download update after $maxRetries attempts.");
  }

  static Future<void> _installApk(BuildContext context, String apkPath) async {
    try {
      if (await Permission.requestInstallPackages.isGranted) {
        final result = await OpenFile.open(apkPath);
        if (result.type != ResultType.done) {
          Fluttertoast.showToast(msg: "Failed to open the installer. Retrying...");
          await Future.delayed(Duration(seconds: 2));
          await checkForUpdate(context);
        }
      } else {
        final status = await Permission.requestInstallPackages.request();
        if (status.isGranted) {
          final result = await OpenFile.open(apkPath);
          if (result.type != ResultType.done) {
            Fluttertoast.showToast(msg: "Failed to open the installer. Retrying...");
            await Future.delayed(Duration(seconds: 2));
            await checkForUpdate(context);
          }
        } else {
          Fluttertoast.showToast(msg: "Installation permission denied. Retrying...");
          await Future.delayed(Duration(seconds: 2));
          await checkForUpdate(context);
        }
      }
    } catch (e) {
      print("Error installing APK: $e");
      Fluttertoast.showToast(msg: "Failed to install update. Retrying...");
      await Future.delayed(Duration(seconds: 2));
      await checkForUpdate(context);
    } finally {
      isUpdating = false;
    }
  }
}