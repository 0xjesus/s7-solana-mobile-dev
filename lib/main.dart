import 'package:flutter/material.dart';
import 'package:pinenacl/x25519.dart' show Box, PrivateKey, PublicKey;
import 'package:uni_links/uni_links.dart';
import 'dart:async';
import 'dart:convert';
import 'package:pinenacl/api.dart'
    show ByteList, ByteListExtension, EncryptedMessage, IntListExtension, PineNaClUtils;
import 'package:bs58/bs58.dart' as bs58;
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

const String appScheme = 'myflutterapp';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phantom dApp',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Color(0xFF1E1E1E),
        hintColor: Colors.blueAccent,
        textTheme: TextTheme(bodyText1: TextStyle(color: Colors.white)),
        appBarTheme: AppBarTheme(
          color: Color(0xFF121212),
          iconTheme: IconThemeData(color: Colors.blueAccent),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.blueAccent,
        ),
      ),
      home: PhantomExample(),
    );
  }
}

class PhantomExample extends StatefulWidget {
  @override
  _PhantomExampleState createState() => _PhantomExampleState();
}

class _PhantomExampleState extends State<PhantomExample> {
  StreamSubscription? _sub;
  String? _deepLinkURL;
  PrivateKey? dappPrivateKey;
  PublicKey? dappPublicKey;
  Box? box;
  String? session;
  String? phantomPublicKey;
  List<String> logs = [];
  String? walletAddress;
  bool _loading = false;

  // Variables for image capture and location
  XFile? _capturedImage;
  String? _status;
  Position? _position;

  // Variable to store the memo
  String? _memo;

  // Variable to store the transaction signature
  String? _transactionSignature;

  @override
  void initState() {
    super.initState();
    initUniLinks();
    dappPrivateKey = PrivateKey.generate();
    dappPublicKey = dappPrivateKey!.publicKey;
  }

  Future<void> initUniLinks() async {
    try {
      Uri? initialUri = await getInitialUri();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } on Exception catch (e) {
      print('Error obtaining initialUri: $e');
    }

    _sub = uriLinkStream.listen((Uri? uri) {
      if (!mounted) return;
      if (uri != null) {
        _handleDeepLink(uri);
      }
    }, onError: (Object err) {
      print('Error in uriLinkStream: $err');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void addLog(String message) {
    setState(() {
      logs.add(message);
    });
    print(message);
  }

  void _handleDeepLink(Uri uri) {
    print('Deep Link received: $uri');
    setState(() {
      _deepLinkURL = uri.toString();
    });
    Map<String, String> params = uri.queryParameters;
    if (params.containsKey('errorCode')) {
      String errorMessage = params['errorMessage'] ?? 'Unknown error';
      addLog('Error: $errorMessage');
      _showSnackBar('Error: $errorMessage', Icons.error, Colors.red);
      return;
    }

    String host = uri.host.toLowerCase();

    if (host == 'onconnect') {
      var phantomEncryptionPublicKey = params['phantom_encryption_public_key'];
      var nonce = params['nonce'];
      var data = params['data'];

      if (phantomEncryptionPublicKey != null && nonce != null && data != null) {
        try {
          Uint8List phantomPublicKeyBytes = bs58.base58.decode(phantomEncryptionPublicKey);
          PublicKey phantomPubKey = PublicKey(phantomPublicKeyBytes);

          // Initialize the box with the correct keys
          box = Box(myPrivateKey: dappPrivateKey!, theirPublicKey: phantomPubKey);

          // Decrypt the payload
          Map<String, dynamic> decryptedData = decryptPayload(data, nonce);

          session = decryptedData['session'];
          phantomPublicKey = decryptedData['public_key'];
          setState(() {
            walletAddress = phantomPublicKey;
          });
          addLog('Wallet Address: $phantomPublicKey');
          _showSnackBar('Connected to Phantom Wallet!', Icons.check_circle, Colors.green);
        } catch (e) {
          addLog('Error handling the deep link: ${e.toString()}');
          _showSnackBar('Error handling the deep link.', Icons.error, Colors.red);
        }
      } else {
        addLog('Missing required parameters in the deep link.');
        _showSnackBar('Missing parameters in the link.', Icons.warning, Colors.orange);
      }
    } else if (host == 'onsignandsendtransaction') {
      // Handle sign and send transaction similarly with proper error handling
      var nonce = params['nonce'];
      var data = params['data'];

      if (nonce != null && data != null) {
        try {
          Map<String, dynamic> decryptedData = decryptPayload(data, nonce);
          var transactionSignature = decryptedData['signature'];
          if (transactionSignature != null) {
            _transactionSignature = transactionSignature;
            addLog('Transaction sent. Signature: $transactionSignature');
            setState(() {
              _status = "Transaction sent successfully.";
              walletAddress = phantomPublicKey; // Ensure wallet address is updated
            });
            _showSnackBar('Transaction sent successfully!', Icons.check_circle, Colors.green);
          } else {
            addLog('No signature received.');
            _showSnackBar('No signature received.', Icons.error, Colors.red);
          }
        } catch (e) {
          addLog('Error decrypting the transaction: ${e.toString()}');
          _showSnackBar('Error decrypting the transaction.', Icons.error, Colors.red);
        }
      }
    } else {
      print('Unrecognized route in the deep link: ${uri.host}');
    }
  }

  Map<String, dynamic> decryptPayload(String data, String nonce) {
    try {
      if (box == null) throw Exception('Box not initialized');
      Uint8List cipherText = bs58.base58.decode(data);
      Uint8List nonceBytes = bs58.base58.decode(nonce);

      EncryptedMessage encryptedMessage = EncryptedMessage(nonce: nonceBytes, cipherText: cipherText);

      Uint8List decrypted = box!.decrypt(encryptedMessage).toUint8List();

      String jsonString = utf8.decode(decrypted);

      return json.decode(jsonString);
    } catch (e) {
      print('Decryption error: ${e.toString()}');
      addLog('Error decrypting: ${e.toString()}');
      throw Exception('Decryption failed: ${e.toString()}');
    }
  }

  Map<String, Uint8List> encryptPayload(Map<String, dynamic> payload) {
    if (box == null) throw Exception('Box not initialized');
    Uint8List nonce = PineNaClUtils.randombytes(24);
    Uint8List message = Uint8List.fromList(utf8.encode(json.encode(payload)));

    final encryptedMessage = box!.encrypt(message, nonce: nonce);

    Uint8List encryptedPayload = encryptedMessage.cipherText.toUint8List();

    return {'nonce': nonce, 'payload': encryptedPayload};
  }

  void connect() async {
    String dappEncryptionPublicKey = bs58.base58.encode(dappPublicKey!.asTypedList);
    String cluster = 'mainnet-beta';
    String appUrl = 'https://phantom.app';
    String redirectLink = '$appScheme://onConnect';

    Uri url = Uri.https('phantom.app', '/ul/v1/connect', {
      'dapp_encryption_public_key': dappEncryptionPublicKey,
      'cluster': cluster,
      'app_url': appUrl,
      'redirect_link': redirectLink,
    });

    String urlStr = url.toString();

    if (await canLaunch(urlStr)) {
      await launchUrl(Uri.parse(urlStr)); // Use launchUrl for more reliable link opening
    } else {
      _showSnackBar('Could not open the Phantom connection link.', Icons.error, Colors.red);
    }
  }

  // Method to capture image, get location, and construct the transaction
  Future<void> signTransaction() async {
    setState(() {
      _loading = true; // Start loading
    });

    final permissionStatus = await Permission.camera.request();

    if (permissionStatus.isGranted) {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);

      if (image != null) {
        setState(() {
          _capturedImage = image;
          _status = "Image captured successfully.";
        });

        _position = await _getCurrentLocation();
        if (_position != null) {
          addLog('Location captured: Latitude ${_position!.latitude}, Longitude ${_position!.longitude}');

          // Call the API to upload image and get the transaction
          String? transactionBase64 = await _uploadImageAndGetTransaction(_position!);
          if (transactionBase64 != null) {
            addLog('Transaction obtained successfully.');
            _showSnackBar('Transaction obtained successfully!', Icons.check_circle, Colors.green);

            // Sign and send the transaction
            await _signAndSendTransaction(transactionBase64);
          } else {
            addLog('Failed to obtain transaction.');
            _showSnackBar('Failed to obtain transaction.', Icons.error, Colors.red);
          }
        } else {
          addLog('Could not get the location.');
          _showSnackBar('Could not get the location.', Icons.error, Colors.red);
        }
      } else {
        setState(() {
          _status = "No image captured.";
        });
        _showSnackBar('No image captured.', Icons.warning, Colors.orange);
      }
    } else {
      setState(() {
        _status = "Camera permission denied.";
      });
      _showSnackBar('Camera permission denied.', Icons.error, Colors.red);
    }

    setState(() {
      _loading = false; // Stop loading
    });
  }

  // Method to sign and send the transaction
  Future<void> _signAndSendTransaction(String transactionBase64) async {
    try {
      setState(() {
        _loading = true; // Start loading when signing
      });

      // Decode the transaction from base64 to bytes
      Uint8List transactionBytes = base64.decode(transactionBase64);

      // Encode the transaction to base58
      String transactionBase58 = bs58.base58.encode(transactionBytes);

      Map<String, dynamic> payload = {
        'session': session,
        'transaction': transactionBase58,
      };

      // Encrypt the payload
      Map<String, Uint8List> encrypted = encryptPayload(payload);
      String dappEncryptionPublicKey = bs58.base58.encode(dappPublicKey!.asTypedList);
      String nonceBase58 = bs58.base58.encode(encrypted['nonce']!);
      String payloadBase58 = bs58.base58.encode(encrypted['payload']!);

      Uri url = Uri.https('phantom.app', '/ul/v1/signAndSendTransaction', {
        'dapp_encryption_public_key': dappEncryptionPublicKey,
        'nonce': nonceBase58,
        'redirect_link': '$appScheme://onSignAndSendTransaction',
        'payload': payloadBase58,
      });

      String urlStr = url.toString();
      print('URL for signing and sending transaction: $urlStr');

      if (await canLaunch(urlStr)) {
        await launchUrl(Uri.parse(urlStr)); // Open the link reliably
      } else {
        throw 'Could not open the signing link.';
      }
    } catch (e) {
      addLog('Error signing and sending the transaction: $e');
      _showSnackBar('Error signing the transaction.', Icons.error, Colors.red);
    } finally {
      setState(() {
        _loading = false; // Stop loading after signing
      });
    }
  }

  // Method to get the current location
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = "Location services are disabled.";
      });
      _showSnackBar('Location services are disabled.', Icons.error, Colors.red);
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _status = "Location permissions are denied.";
        });
        _showSnackBar('Location permissions are denied.', Icons.error, Colors.red);
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _status = "Location permissions are permanently denied.";
      });
      _showSnackBar('Location permissions are permanently denied.', Icons.error, Colors.red);
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  // Method to upload the image and get the transaction
  Future<String?> _uploadImageAndGetTransaction(Position position) async {
    setState(() {
      _status = "Sending image and location to the server...";
    });

    try {
      final uri = Uri.parse('https://solpay-api.cryptoadvisor.tech/solana/upload-and-create-collection');

      final request = http.MultipartRequest('POST', uri)
        ..fields['fromPubKey'] = phantomPublicKey ?? ''
        ..fields['latitude'] = position.latitude.toString()
        ..fields['longitude'] = position.longitude.toString()
        ..files.add(await http.MultipartFile.fromPath('file', _capturedImage!.path));

      final response = await request.send();

      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final responseData = jsonDecode(responseBody);
        final String transactionBase64 = responseData['data']['transaction'];
        setState(() {
          _status = "Transaction obtained successfully.";
        });
        return transactionBase64;
      } else {
        print("Error in server response: $responseBody");
        setState(() {
          _status = "Error obtaining transaction: ${response.statusCode} ${response.reasonPhrase}";
        });
        return null;
      }
    } catch (e) {
      print("Exception obtaining transaction: $e");
      setState(() {
        _status = "Error obtaining transaction: $e";
      });
      return null;
    }
  }

  // Method to open the Solscan URL
  void _openSolscan() async {
    if (_transactionSignature != null) {
      final url = 'https://solscan.io/tx/$_transactionSignature';
      final Uri uri = Uri.parse(url);

      try {
        // Directly attempt to launch the URL
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // Ensures the URL opens in an external app
        );
      } catch (e) {
        setState(() {
          _status = "Failed to open Solscan.";
        });
        _showSnackBar('Failed to open Solscan: $e', Icons.error, Colors.red);
      }
    } else {
      setState(() {
        _status = "No transaction to show.";
      });
      _showSnackBar('No transaction to show.', Icons.error, Colors.red);
    }
  }


  void _showSnackBar(String message, IconData icon, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color),
            SizedBox(width: 10),
            Flexible(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.black87,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Phantom dApp'),
        actions: [
          if (walletAddress == null)
            IconButton(
              icon: Icon(Icons.link),
              onPressed: connect,
              tooltip: 'Connect to Phantom',
            ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      _buildConnectionCard(),
                      _buildCapturedImageSection(),
                      _buildLocationSection(),
                      _buildTransactionSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            Center(
              child: CircularProgressIndicator(), // Loading indicator when _loading is true
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: signTransaction,
        icon: Icon(Icons.camera_alt),
        label: Text('Capture & Sign'),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      color: Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: 10),
      child: ListTile(
        leading: Icon(Icons.account_balance_wallet, color: Colors.blueAccent),
        title: walletAddress != null
            ? Text('Connected Wallet: $walletAddress', style: TextStyle(color: Colors.white))
            : Text('No Wallet Connected', style: TextStyle(color: Colors.redAccent)),
        trailing: walletAddress == null
            ? ElevatedButton.icon(
          onPressed: connect,
          icon: Icon(Icons.link),
          label: Text('Connect'),
        )
            : null,
      ),
    );
  }

  Widget _buildCapturedImageSection() {
    if (_capturedImage == null) return SizedBox.shrink();
    return Card(
      color: Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(Icons.image, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('Captured Image:', style: TextStyle(fontSize: 16, color: Colors.white)),
              ],
            ),
          ),
          Image.file(
            File(_capturedImage!.path),
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    if (_position == null) return SizedBox.shrink();
    return Card(
      color: Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: 10),
      child: ListTile(
        leading: Icon(Icons.location_on, color: Colors.green),
        title: Text(
          'Location: Latitude ${_position!.latitude}, Longitude ${_position!.longitude}',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildTransactionSection() {
    if (_transactionSignature == null) return SizedBox.shrink();
    return Card(
      color: Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: 10),
      child: ListTile(
        leading: Icon(Icons.receipt_long, color: Colors.blueAccent),
        title: GestureDetector(
          onTap: _openSolscan,
          child: Text(
            'View Transaction on Solscan',
            style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
          ),
        ),
      ),
    );
  }
}
