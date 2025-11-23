import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ImagePumperApp(),
    theme: ThemeData(primarySwatch: Colors.blue),
  ));
}

class ImagePumperApp extends StatefulWidget {
  @override
  _ImagePumperAppState createState() => _ImagePumperAppState();
}

class _ImagePumperAppState extends State<ImagePumperApp> {
  InAppWebViewController? _webViewController;
  String status = "הכנס לקישור ולחץ על 'התחל שאיבה'";
  bool isWorking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("הפומפה - מוריד התמונות")),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.grey[200],
            child: Column(
              children: [
                Text(status, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isWorking ? null : startPumping,
                      icon: Icon(Icons.download),
                      label: Text("התחל שאיבה"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                    ElevatedButton.icon(
                      onPressed: stopPumping,
                      icon: Icon(Icons.stop),
                      label: Text("עצור"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri("https://www.google.com")),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStop: (controller, url) async {
                // לוודא הרשאת אחסון בכל פעם שדף נטען
                await Permission.storage.request();
                await Permission.manageExternalStorage.request();
              },
            ),
          ),
        ],
      ),
    );
  }

  void stopPumping() {
    setState(() {
      isWorking = false;
      status = "עצרת את הפעולה.";
    });
  }

  Future<void> startPumping() async {
    // 1. קבלת אישור לשמור קבצים
    if (await Permission.storage.request().isDenied) {
      // נסיון נוסף לאנדרואיד חדש
       await Permission.manageExternalStorage.request();
    }

    setState(() {
      isWorking = true;
      status = "מתחיל לעבוד... נא לא לגעת במסך";
    });

    // יצירת תיקייה ראשית ב-Download
    Directory dir = Directory('/storage/emulated/0/Download/PumperApp');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    int noChangeCount = 0;
    int lastHeight = 0;

    // הלולאה שעושה את הקסם: גלילה ושאיבה
    while (isWorking) {
      // א. מוריד תמונות מהמסך הנוכחי
      await downloadVisibleImages(dir);

      // ב. גולל למטה
      await _webViewController?.evaluateJavascript(source: "window.scrollBy(0, document.body.scrollHeight);");

      // ג. מחכה לטעינה (4 שניות)
      setState(() => status = "גולל וממתין לטעינה...");
      await Future.delayed(Duration(seconds: 4));

      // ד. בדיקה אם הגענו לסוף
      var heightResult = await _webViewController?.evaluateJavascript(source: "document.body.scrollHeight");
      int currentHeight = int.tryParse(heightResult.toString()) ?? 0;

      if (currentHeight == lastHeight) {
        noChangeCount++;
        if (noChangeCount >= 3) { // אם 3 פעמים הגובה לא השתנה - סיימנו
          setState(() {
            isWorking = false;
            status = "סיימנו! כל התמונות ירדו לתיקיית Downloads/PumperApp";
          });
          break;
        }
      } else {
        noChangeCount = 0;
        lastHeight = currentHeight;
      }
    }
  }

  Future<void> downloadVisibleImages(Directory dir) async {
    // שולף את כל ה-src של התמונות מהדף
    var result = await _webViewController?.evaluateJavascript(source: """
      Array.from(document.querySelectorAll('img')).map(img => img.src);
    """);

    List<dynamic> urls = result ?? [];

    for (var urlObj in urls) {
      if (!isWorking) return;
      String url = urlObj.toString();

      // סינון: רק קבצי תמונה חוקיים
      if (url.startsWith("http") && (url.contains(".jpg") || url.contains(".png") || url.contains(".jpeg"))) {
        try {
          // שם קובץ ייחודי כדי למנוע כפילויות
          String filename = url.split('/').last.split('?').first;
          String uniqueFilename = DateTime.now().millisecondsSinceEpoch.toString() + "_" + filename;
          File file = File("${dir.path}/$uniqueFilename");

          // הורדה (מניעת כפילויות תתרחש רק אם שני קבצים זהים ירדו באותו מילישנייה)
          if (!file.existsSync()) {
             await Dio().download(url, file.path);
          }

        } catch (e) {
          print("שגיאה בהורדה נקודתית: $e");
        }
      }
    }
  }
}
