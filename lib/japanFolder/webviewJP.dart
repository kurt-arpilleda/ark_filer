import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../pdfViewer.dart';
import '../api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../auto_update.dart';
import 'api_serviceJP.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:unique_identifier/unique_identifier.dart';
import '../barcode_scanner_screen.dart';

class SoftwareWebViewScreenJP extends StatefulWidget {
  final int linkID;

  SoftwareWebViewScreenJP({required this.linkID});

  @override
  _SoftwareWebViewScreenState createState() => _SoftwareWebViewScreenState();
}

class _SoftwareWebViewScreenState extends State<SoftwareWebViewScreenJP> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiService apiService = ApiService();
  final ApiServiceJP apiServiceJP = ApiServiceJP();

  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  bool _isNavigating = false;
  Timer? _debounceTimer;
  String? _webUrl;
  String? _profilePictureUrl;
  String? _firstName;
  String? _surName;
  String? _idNumber;
  bool _isLoading = true;
  int? _currentLanguageFlag;
  double _progress = 0;
  String? _phOrJp;
  bool _isPhCountryPressed = false;
  bool _isJpCountryPressed = false;
  bool _isCountryDialogShowing = false;
  bool _isCountryLoadingPh = false;
  bool _isCountryLoadingJp = false;
  bool _isDownloadDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializePullToRefresh();
    _fetchInitialData();
    _checkForUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    webViewController?.stopLoading();
    pullToRefreshController?.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only check for updates if we're not already in the middle of an update
      if (!AutoUpdate.isUpdating) {
        _checkForUpdates();
      }
    }
  }
  void _initializePullToRefresh() {
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.blue,
      ),
      onRefresh: () async {
        if (webViewController != null) {
          _fetchAndLoadUrl();
        }
      },
    );
  }

  Future<void> _checkForUpdates() async {
    try {
      await AutoUpdate.checkForUpdate(context);
    } catch (e) {
      // Handle error if update check fails
      debugPrint('Update check failed: $e');
    }
  }

  Future<void> _fetchInitialData() async {
    await _fetchDeviceInfo();
    await _loadCurrentLanguageFlag();
    await _fetchAndLoadUrl();
    await _loadPhOrJp();
  }
  Future<void> _fetchDeviceInfo() async {
    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        throw Exception("Unable to get device ID");
      }

      final deviceResponse = await apiServiceJP.checkDeviceId(deviceId);
      if (deviceResponse['success'] == true && deviceResponse['idNumber'] != null) {
        // Store the IDNumber in SharedPreferences (in case it's not already saved by the API)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('IDNumberJP', deviceResponse['idNumber']);

        setState(() {
          _idNumber = deviceResponse['idNumber'];
        });
        await _fetchProfile(_idNumber!);
      }
    } catch (e) {
      print("Error fetching device info: $e");
    }
  }

  Future<void> _loadPhOrJp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp');
    });
  }

  Future<void> _fetchProfile(String idNumber) async {
    try {
      final profileData = await apiServiceJP.fetchProfile(idNumber);
      if (profileData["success"] == true) {
        String profilePictureFileName = profileData["picture"];

        String primaryUrl = "${ApiServiceJP.apiUrls[0]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isPrimaryUrlValid = await _isImageAvailable(primaryUrl);

        String fallbackUrl = "${ApiServiceJP.apiUrls[1]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isFallbackUrlValid = await _isImageAvailable(fallbackUrl);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('languageFlagJP', profileData["languageFlag"]);
        setState(() {
          _firstName = profileData["firstName"];
          _surName = profileData["surName"];
          _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
          _currentLanguageFlag = profileData["languageFlag"] ?? _currentLanguageFlag ?? 2;
        });
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  Future<bool> _isImageAvailable(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchAndLoadUrl() async {
    try {
      String url = await apiServiceJP.fetchSoftwareLink(widget.linkID);
      if (mounted) {
        setState(() {
          _webUrl = url;
          _isLoading = true;
        });
        if (webViewController != null) {
          await webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        }
      }
    } catch (e) {
      debugPrint("Error fetching link: $e");
    }
  }

  Future<void> _loadCurrentLanguageFlag() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguageFlag = prefs.getInt('languageFlagJP');
    });
  }

  Future<void> _updateLanguageFlag(int flag) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (_idNumber != null) {
      setState(() {
        _currentLanguageFlag = flag;
      });
      try {
        await apiServiceJP.updateLanguageFlag(_idNumber!, flag);
        await prefs.setInt('languageFlagJP', flag);

        if (webViewController != null) {
          WebUri? currentUri = await webViewController!.getUrl();
          if (currentUri != null) {
            await webViewController!.loadUrl(urlRequest: URLRequest(url: currentUri));
          } else {
            _fetchAndLoadUrl();
          }
        }
      } catch (e) {
        print("Error updating language flag: $e");
      }
    }
  }

  Future<void> _updatePhOrJp(String value) async {
    if ((value == 'ph' && _isCountryLoadingPh) || (value == 'jp' && _isCountryLoadingJp)) {
      return;
    }

    setState(() {
      if (value == 'ph') {
        _isCountryLoadingPh = true;
        _isPhCountryPressed = true;
      } else {
        _isCountryLoadingJp = true;
        _isJpCountryPressed = true;
      }
    });

    await Future.delayed(Duration(milliseconds: 100));

    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      // Get the appropriate service based on the selected country
      dynamic service = value == "jp" ? apiServiceJP : apiService;

      // Check device ID for the selected country
      final deviceResponse = await service.checkDeviceId(deviceId);

      if (deviceResponse['success'] != true || deviceResponse['idNumber'] == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      // If registered, proceed with the update
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('phorjp', value);
      setState(() {
        _phOrJp = value;
      });

      if (value == "ph") {
        Navigator.pushReplacementNamed(context, '/webView');
      } else if (value == "jp") {
        Navigator.pushReplacementNamed(context, '/webViewJP');
      }
    } catch (e) {
      print("Error updating country preference: $e");
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "デバイス登録の確認中にエラーが発生しました: ${e.toString()}"
            : "Error checking device registration: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
    } finally {
      setState(() {
        if (value == 'ph') {
          _isCountryLoadingPh = false;
          _isPhCountryPressed = false;
        } else {
          _isCountryLoadingJp = false;
          _isJpCountryPressed = false;
        }
      });
    }
  }
  void _showCountryLoginDialog(BuildContext context, String country) {
    if (_isCountryDialogShowing) return;

    _isCountryDialogShowing = true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Image.asset(
                country == 'ph' ?  'assets/images/philippines.png' :  'assets/images/japan.png',
                width: 26,
                height: 26,
              ),
              SizedBox(width: 8),
              Text(
                _currentLanguageFlag == 2 ? "ログインが必要です" : "Login Required",
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
          content: Text(
            country == 'ph'
                ? (_currentLanguageFlag == 2
                ? "まずARK LOG PHアプリにログインしてください"
                : "Please login to ARK LOG PH App first")
                : (_currentLanguageFlag == 2
                ? "まずARK LOG JPアプリにログインしてください"
                : "Please login to ARK LOG JP App first"),
          ),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                _isCountryDialogShowing = false;
              },
            ),
          ],
        );
      },
    ).then((_) {
      _isCountryDialogShowing = false;
    });
  }

  Future<bool> _onWillPop() async {
    if (webViewController != null && await webViewController!.canGoBack()) {
      webViewController!.goBack();
      return false;
    } else {
      return true;
    }
  }
  bool _isPdfUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    if (url.toLowerCase().endsWith('.pdf')) {
      return true;
    }

    final mimeType = lookupMimeType(url);
    if (mimeType == 'application/pdf') {
      return true;
    }

    if (uri.pathSegments.last.toLowerCase().contains('pdf')) {
      return true;
    }

    return false;
  }

  Future<void> _launchInBrowser(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } else {
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "ブラウザを起動できませんでした"
            : "Could not launch browser",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _viewPdfInternally(String url) async {
    try {
      final uri = Uri.parse(url);
      String fileName = uri.pathSegments.last;
      if (!fileName.toLowerCase().endsWith('.pdf')) {
        fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PDFViewerScreen(
            pdfUrl: url,
            fileName: fileName,
            languageFlag: _currentLanguageFlag ?? 1,
          ),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "PDFを開く際にエラーが発生しました"
            : "Error opening PDF",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
      await _launchInBrowser(url);
    }
  }

  void _showDownloadDialog(String url, bool isPdf) {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (_isDownloadDialogShowing) return;

    _isDownloadDialogShowing = true;

    final uri = Uri.parse(url);
    String fileName = uri.pathSegments.last;

    if (fileName.isEmpty || fileName.length > 50) {
      fileName = isPdf
          ? 'document_${DateTime.now().millisecondsSinceEpoch}.pdf'
          : 'file_${DateTime.now().millisecondsSinceEpoch}';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.35,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              _currentLanguageFlag == 2 ? 'ダウンロード' : 'Download',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 15),
            Text(
              _currentLanguageFlag == 2 ? 'ファイル名:' : 'File name:',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                fileName,
                style: TextStyle(fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      _currentLanguageFlag == 2 ? 'キャンセル' : 'Cancel',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      if (isPdf) {
                        await _viewPdfInternally(url);
                      } else {
                        await _launchInBrowser(url);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isPdf
                          ? (_currentLanguageFlag == 2 ? '表示' : 'View')
                          : (_currentLanguageFlag == 2 ? 'ダウンロード' : 'Download'),
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).then((_) {
      // Reset the flag when dialog is dismissed
      _isDownloadDialogShowing = false;
    });
  }

  // Function to check if a URL is a download link
  bool _isDownloadableUrl(String url) {
    final mimeType = lookupMimeType(url);
    if (mimeType == null) return false;

    // List of common download file extensions
    const downloadableExtensions = [
      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
      'zip', 'rar', '7z', 'tar', 'gz',
      'apk', 'exe', 'dmg', 'pkg',
      'jpg', 'jpeg', 'png', 'gif', 'bmp',
      'mp3', 'wav', 'ogg',
      'mp4', 'avi', 'mov', 'mkv',
      'txt', 'csv', 'json', 'xml'
    ];

    return downloadableExtensions.any((ext) => url.toLowerCase().contains('.$ext'));
  }

  Future<void> _showInputMethodPicker() async {
    try {
      if (Platform.isAndroid) {
        const MethodChannel channel = MethodChannel('input_method_channel');
        await channel.invokeMethod('showInputMethodPicker');
      } else {
        // iOS doesn't have this capability
        Fluttertoast.showToast(
          msg: "Keyboard selection is only available on Android",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint("Error showing input method picker: $e");
    }
  }
  Future<void> _debounceNavigation(String url) async {
    if (_isNavigating) return;

    // Cancel any pending navigation
    _debounceTimer?.cancel();

    setState(() {
      _isNavigating = true;
    });

    _debounceTimer = Timer(Duration(milliseconds: 500), () async {
      try {
        await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } catch (e) {
        debugPrint("Navigation error: $e");
      } finally {
        if (mounted) {
          setState(() {
            _isNavigating = false;
          });
        }
      }
    });
  }
  Future<void> _openBarcodeScanner() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const BarcodeScannerScreen(),
        ),
      );

      if (result != null && result is String && result.isNotEmpty) {
        // Inject the scanned code into the focused input field
        await _injectBarcodeIntoWebView(result);
      }
    } catch (e) {
      print('Error opening barcode scanner: $e');
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "バーコードスキャナーを開けませんでした"
            : "Could not open barcode scanner",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  Future<void> _injectBarcodeIntoWebView(String barcode) async {
    if (webViewController != null) {
      try {
        String jsCode = '''
    async function injectBarcode() {
      const activeElement = document.activeElement;
      const inputs = document.querySelectorAll('input[type="text"], input[type="search"], input[type="number"], textarea');
      const targetInput = activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') 
        ? activeElement 
        : inputs.length > 0 ? inputs[0] : null;

      if (!targetInput) return 'no_input_found';

      // Focus and set value
      targetInput.focus();
      targetInput.value = '$barcode';

      // Trigger input event
      targetInput.dispatchEvent(new Event('input', { bubbles: true }));
      await new Promise(resolve => setTimeout(resolve, 50));

      // Trigger change event
      targetInput.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise(resolve => setTimeout(resolve, 50));

      // Create and dispatch Enter key sequence with delays
      const enterEvent = (type) => new KeyboardEvent(type, {
        key: 'Enter',
        code: 'Enter',
        keyCode: 13,
        which: 13,
        bubbles: true,
        cancelable: true
      });

      targetInput.dispatchEvent(enterEvent('keydown'));
      await new Promise(resolve => setTimeout(resolve, 20));

      targetInput.dispatchEvent(enterEvent('keypress'));
      await new Promise(resolve => setTimeout(resolve, 20));

      targetInput.dispatchEvent(enterEvent('keyup'));
      await new Promise(resolve => setTimeout(resolve, 50));

      // Try to submit form if exists
      if (targetInput.form) {
        targetInput.form.dispatchEvent(new Event('submit', { bubbles: true }));
      }

      // Blur the input field to close keyboard
      await new Promise(resolve => setTimeout(resolve, 100));
      targetInput.blur();

      return 'success';
    }

    injectBarcode().then(result => result);
    ''';

        final result = await webViewController!.evaluateJavascript(source: jsCode);
        print('Barcode injection result: $result');

        Fluttertoast.showToast(
          msg: _currentLanguageFlag == 2
              ? "バーコードが入力されました: $barcode"
              : "Barcode entered: $barcode",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );

      } catch (e) {
        print('Error injecting barcode: $e');
        Fluttertoast.showToast(
          msg: _currentLanguageFlag == 2
              ? "バーコードの入力に失敗しました"
              : "Failed to enter barcode",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  Future<void> _setupInputFieldDetection() async {
    if (webViewController != null) {
      String jsCode = '''
(function() {
  let button;
  let container;

  function isVisible(elem) {
    if (!elem || elem.offsetParent === null) return false;
    
    const rect = elem.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    
    const topElem = document.elementFromPoint(centerX, centerY);
    return topElem === elem || elem.contains(topElem);
  }

  function updateBarcodeScannerButton() {
    const input = document.getElementById('lotNumber');
    if (!input) return;

    const shouldShow = isVisible(input);

    // If it should be visible and not already added
    if (shouldShow && !input.dataset.hasBarcodeButton) {
      input.dataset.hasBarcodeButton = 'true';

      container = document.createElement('div');
      container.style.position = 'relative';
      container.style.display = 'inline-block';
      container.style.width = '100%';

      input.parentNode.insertBefore(container, input);
      container.appendChild(input);

      button = document.createElement('div');
      button.innerHTML = '𝄃𝄂𝄂𝄀𝄁𝄃';
      button.style.cssText = \`
        position: absolute;
        right: 8px;
        top: 50%;
        transform: translateY(-50%);
        z-index: 9999;
        background: #3452B4;
        color: white;
        padding: 0 4px;
        border-radius: 4px;
        font-size: 10px;
        cursor: pointer;
        box-shadow: 0 1px 3px rgba(0,0,0,0.2);
        font-family: Arial, sans-serif;
        height: 24px;
        display: flex;
        align-items: center;
        justify-content: center;
      \`;

      button.onclick = function(e) {
        e.stopPropagation();
        window.flutter_inappwebview.callHandler('openBarcodeScanner');
      };

      container.appendChild(button);
    }

    // If the input is now hidden or behind modal, remove the button
    if (!shouldShow && button && container && container.parentNode) {
      input.removeAttribute('data-has-barcode-button');
      container.parentNode.insertBefore(input, container);
      container.remove();
      button = null;
      container = null;
    }
  }

  // Initial check
  updateBarcodeScannerButton();

  // Observe DOM for changes (e.g., modal open/close)
  const observer = new MutationObserver(function() {
    updateBarcodeScannerButton();
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['style', 'class']
  });

  // Also check every second in case changes aren't caught by observer
  setInterval(updateBarcodeScannerButton, 1000);
})();
''';

      try {
        await webViewController!.evaluateJavascript(source: jsCode);
      } catch (e) {
        print('Error setting up input field detection: \$e');
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight - 20),
          child: SafeArea(
            child: AppBar(
              backgroundColor: Color(0xFF3452B4),
              centerTitle: true,
              toolbarHeight: kToolbarHeight - 20,
              leading: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 30,
                icon: Icon(
                  Icons.settings,
                  color: Colors.white,
                ),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
              // title: _idNumber != null
              //     ? Text(
              //   "ID: $_idNumber",
              //   style: TextStyle(
              //     color: Colors.white,
              //     fontSize: 14,
              //     fontWeight: FontWeight.w500,
              //     letterSpacing: 0.5,
              //     shadows: [
              //       Shadow(
              //         color: Colors.black.withOpacity(0.2),
              //         blurRadius: 2,
              //         offset: Offset(1, 1),
              //       ),
              //     ],
              //   ),
              // )
              //     : null,
              actions: [
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 25,
                  icon: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  onPressed: () {
                    if (Platform.isIOS) {
                      exit(0);
                    } else {
                      SystemNavigator.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        drawer: SizedBox(
          width: MediaQuery.of(context).size.width * 0.70,
          child: Drawer(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            color: Color(0xFF2053B3),
                            padding: EdgeInsets.only(top: 50, bottom: 20),
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.white,
                                    backgroundImage: _profilePictureUrl != null
                                        ? NetworkImage(_profilePictureUrl!)
                                        : null,
                                    child: _profilePictureUrl == null
                                        ? FlutterLogo(size: 60)
                                        : null,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  _firstName != null && _surName != null
                                      ? "$_firstName $_surName"
                                      : _currentLanguageFlag == 2
                                      ? "ユーザー名"
                                      : "User Name",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      overflow: TextOverflow.ellipsis,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 5),
                                if (_idNumber != null)
                                  Text(
                                    "ID: $_idNumber",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,  // Medium weight
                                      letterSpacing: 0.5,          // Slightly spaced out letters
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 2,
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _currentLanguageFlag == 2 ? 35.0 : 16.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? '言語'
                                      : 'Language',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 25),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(1),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/americanFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 1)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 30),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(2),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/japaneseFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 2)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? 'キーボード'
                                      : 'Keyboard',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15), // Adjust this value as needed
                                IconButton(
                                  icon: Icon(Icons.keyboard, size: 28),
                                  iconSize: 28,
                                  onPressed: () {
                                    _showInputMethodPicker();
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: EdgeInsets.only(
                              left: _currentLanguageFlag == 2 ? 46.0 : 30.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? '手引き'
                                      : 'Manual',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15),
                                IconButton(
                                  icon: Icon(Icons.menu_book, size: 28),
                                  iconSize: 28,
                                  onPressed: () async {
                                    if (_idNumber == null || _currentLanguageFlag == null) return;

                                    try {
                                      final manualUrl = await apiService.fetchManualLink(widget.linkID, _currentLanguageFlag!);
                                      final fileName = 'manual_${widget.linkID}_${_currentLanguageFlag}.pdf';

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PDFViewerScreen(
                                            pdfUrl: manualUrl,
                                            fileName: fileName,
                                            languageFlag: _currentLanguageFlag!, // Add this line
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      Fluttertoast.showToast(
                                        msg: _currentLanguageFlag == 2
                                            ? "マニュアルの読み込み中にエラーが発生しました: ${e.toString()}"
                                            : "Error loading manual: ${e.toString()}",
                                        toastLength: Toast.LENGTH_LONG,
                                        gravity: ToastGravity.BOTTOM,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: EdgeInsets.only(
                              left: _currentLanguageFlag == 2 ? 58.0 : 32.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? 'メモ'
                                      : 'Memo',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15),
                                IconButton(
                                  icon: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Color(0xFFE91E63),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: Offset(2, 2),
                                        ),
                                      ],
                                    ),
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()..scale(-1.0, 1.0),
                                      child: Icon(
                                        Icons.mode_comment_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  onPressed: () async {
                                    // Close the drawer first
                                    Navigator.of(context).pop();

                                    if (webViewController != null) {
                                      try {
                                        await webViewController!.evaluateJavascript(
                                          source: "document.getElementById('memoBtn').click();",
                                        );
                                      } catch (e) {
                                        Fluttertoast.showToast(
                                          msg: _currentLanguageFlag == 2
                                              ? "メモボタンをクリックできませんでした"
                                              : "Could not click memo button",
                                          toastLength: Toast.LENGTH_SHORT,
                                          gravity: ToastGravity.BOTTOM,
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          _currentLanguageFlag == 2
                              ? '国'
                              : 'Country',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 25),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isPhCountryPressed = true),
                          onTapUp: (_) => setState(() => _isPhCountryPressed = false),
                          onTapCancel: () => setState(() => _isPhCountryPressed = false),
                          onTap: () => _updatePhOrJp("ph"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isPhCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/philippines.png',
                                  width: 40,
                                  height: 40,
                                ),
                                // Subtle reload icon (only visible when PH is active and not loading)
                                if (_phOrJp == "ph" && !_isCountryLoadingPh)
                                  Opacity(
                                    opacity: 0.6, // Make it subtle
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                // Loading indicator
                                if (_isCountryLoadingPh)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                // Underline
                                if (_phOrJp == "ph")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 30),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isJpCountryPressed = true),
                          onTapUp: (_) => setState(() => _isJpCountryPressed = false),
                          onTapCancel: () => setState(() => _isJpCountryPressed = false),
                          onTap: () => _updatePhOrJp("jp"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isJpCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/japan.png',
                                  width: 40,
                                  height: 40,
                                ),
                                // Subtle reload icon (only visible when JP is active and not loading)
                                if (_phOrJp == "jp" && !_isCountryLoadingJp)
                                  Opacity(
                                    opacity: 0.6, // Make it subtle
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                // Loading indicator
                                if (_isCountryLoadingJp)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                // Underline
                                if (_phOrJp == "jp")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (_webUrl != null)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_webUrl!)),
                  initialSettings: InAppWebViewSettings(
                    mediaPlaybackRequiresUserGesture: false,
                    javaScriptEnabled: true,
                    useHybridComposition: true,
                    allowsInlineMediaPlayback: true,
                    allowContentAccess: true,
                    allowFileAccess: true,
                    cacheEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    allowUniversalAccessFromFileURLs: true,
                    allowFileAccessFromFileURLs: true,
                    useOnDownloadStart: true,
                    transparentBackground: true,
                    thirdPartyCookiesEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    hardwareAcceleration: true,
                    supportMultipleWindows: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    overScrollMode: OverScrollMode.NEVER,
                    forceDark: ForceDark.OFF,
                    forceDarkStrategy: ForceDarkStrategy.WEB_THEME_DARKENING_ONLY,
                    saveFormData: true,
                    userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36",
                  ),
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) {
                    webViewController = controller;

                    // Add handler for barcode scanner
                    controller.addJavaScriptHandler(
                      handlerName: 'openBarcodeScanner',
                      callback: (args) {
                        _openBarcodeScanner();
                      },
                    );
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      _isLoading = true;
                      _progress = 0;
                    });
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController?.endRefreshing();
                    setState(() {
                      _isLoading = false;
                      _progress = 1;
                    });
                    String scrollScript = """
  function makeDialogScrollable() {
    const dialog = document.querySelector('.tbox');
    if (dialog) {
      // Check if dialog is partially off-screen
      const rect = dialog.getBoundingClientRect();
      const isOffScreen = rect.left < 0 || rect.top < 0 || 
                         rect.right > window.innerWidth || 
                         rect.bottom > window.innerHeight;
      
      if (isOffScreen) {
        // Make dialog container scrollable
        const tinner = dialog.querySelector('.tinner');
        if (tinner) {
          tinner.style.overflow = 'auto';
          tinner.style.maxHeight = '80vh';
          tinner.style.maxWidth = '90vw';
        }
        
        // Make content scrollable if needed
        const tcontent = dialog.querySelector('.tcontent');
        if (tcontent) {
          tcontent.style.overflow = 'auto';
          tcontent.style.maxHeight = '70vh';
        }
      }
    }
  }
  
  // Run initially and set up mutation observer for dynamic dialogs
  makeDialogScrollable();
  
  const observer = new MutationObserver(function(mutations) {
    makeDialogScrollable();
  });
  
  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true
  });
  """;

                    try {
                      await controller.evaluateJavascript(source: scrollScript);
                    } catch (e) {
                      debugPrint("Error making dialog scrollable: $e");
                    }

                    // Setup input field detection after page loads
                    await Future.delayed(Duration(milliseconds: 1000));
                    await _setupInputFieldDetection();
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() {
                      _progress = progress / 100;
                    });
                  },
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url?.toString() ?? '';
                    final isPdf = _isPdfUrl(url);
                    if (_isDownloadableUrl(url)) {
                      await _launchInBrowser(url);
                      return NavigationActionPolicy.CANCEL;
                    }
                    if (isPdf || lookupMimeType(url) != null) {
                      _showDownloadDialog(url, isPdf);
                      return NavigationActionPolicy.CANCEL;
                    }

                    _debounceNavigation(url);
                    return NavigationActionPolicy.CANCEL;
                  },
                  onDownloadStartRequest: (controller, downloadStartRequest) async {
                    final url = downloadStartRequest.url.toString();
                    final isPdf = _isPdfUrl(url);
                    _showDownloadDialog(url, isPdf);
                  },
                ),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}