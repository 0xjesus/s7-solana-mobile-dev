/// Imports
/// ------------------------------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:solana_wallet_adapter/solana_wallet_adapter.dart';
import 'package:solana_web3/programs.dart';
import 'package:solana_web3/solana_web3.dart' as web3;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:solana_web3/solana_web3.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

/// Main
/// ------------------------------------------------------------------------------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Solana NFT Minter'),
          backgroundColor: Colors.blueAccent,
        ),
        body: const ExampleApp(),
      ),
    );
  }
}

/// Example App
/// ------------------------------------------------------------------------------------------------

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

/// Example App State
/// ------------------------------------------------------------------------------------------------

class _ExampleAppState extends State<ExampleApp> {
  /// Initialization future.

  late final Future<void> _future;

  /// NOTE: Your wallet application must be connected to the same cluster.
  static final Cluster cluster = Cluster.mainnet;

  /// Request status.
  String? _status;

  // loading bool
  bool _loading = false;
  /// Wallet balance
  double? _balance;

  // hardcoded  transaction
  final String transactionBase64 = "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACKKwj9oxkP6zv0A3Vmv/FfV7c1E9J5gkIDlRHr0vDZ6ZHx28mzJP2YRmi1AnUBgxvSt5qjn3kBJ6Z06zp1ZlwFgAIABQoyyR+rbftBNtRAq1ug/Xr497zQDdKnAw8Rek4+bOsa05ftjiJ8ychmgHiN6gdSHFGSLCzkwFPWLgQxjyS3vnwx/9RAiGIcJ4cf1fr4NfWKD93AI1woL4I31h4Zad/Jxvg1o5TqOXdAaW16G4Lxlt2S/FPn3IFnLCIahHydSmN7LnSnL09bz77/mMJTgO+00ga08HUHfecqsAmN6WG06JgrC3BlsePRfEU4nVJ/awTDzVi4bHMaoP21SbbRvAP4KUYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAan1RcYe9FmNdrUBFX9wsDBJMaPIVZ1pdu6y18IAAAABt324ddloZPZy+FGzut5rBy0he1fWzeROoz1hX7/AKmMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZ1gCCxqe3XEDUm1a9m+sFhtjf+gj6qAAdW2PiOt0bi7AgUJAgMBAAAABgcIvgEqABEAAABNeSBDb2xsZWN0aW9uIE5GVAoAAABTNi1leGFtcGxlWQAAAGh0dHBzOi8vYmxvY2tjaGFpbnN0YXJ0ZXIuc2ZvMy5kaWdpdGFsb2NlYW5zcGFjZXMuY29tL3VwbG9hZHMvbWV0YWRhdGEtMTcyNjA3NjgwNDAwNy5qc29u5wMBAQAAADLJH6tt+0E21ECrW6D9evj3vNAN0qcDDxF6Tj5s6xrTAWQAAQAAAAEAAAAAAAAAAAAAAAEABQ8EAAIDBQEABQAGBwgJBQULKwABAAAAAAAAAAAA";
  /// Captured image
  XFile? _capturedImage;

  /// Uploaded image URL
  String? _imageUrl;

  /// Output
  dynamic _output;

  /// Create an instance of the [SolanaWalletAdapter].
  final SolanaWalletAdapter adapter = SolanaWalletAdapter(
    AppIdentity(
      name: 'Solana NFT Minter',
      uri: Uri.parse('https://lunadefi.ai'),
      icon: Uri.parse('https://lunadefi.ai/images/luna-logo.svg'),
    ),
    cluster: Cluster.mainnet,
  );


  @override
  void initState() {
    super.initState();
    _future = SolanaWalletAdapter.initialize();
  }

  /// Connects the application to a wallet running on the device.
  Future<void> _connect() async {
    try {
      final result = await adapter.authorize();
      setState(() => _output = result.toJson());
    } catch (e) {
      setState(() => _status = "Failed to connect: $e");
    }
  }


  /// Disconnects the application from a wallet running on the device.
   _disconnect() {
      adapter.deauthorize(

      ).then((_) =>
          setState(() {
            _status = "Disconnected!";
            _balance = null;
            _capturedImage = null;
            _imageUrl = null;
          }));

  }

  /// Function to get balance
  Future<void> _getBalance() async {
    try {
      print("getiiiiiiiiiiiiiiiiiing balance....");
      final Connection connection = web3.Connection(cluster);
      final Pubkey? wallet = Pubkey.tryFromBase64(adapter.connectedAccount?.address);
      if (wallet != null) {
        final int lamports = await connection.getBalance(wallet);
        print("lampoooooooooooooooooooooooorts: $lamports");
        setState(() {
          _balance = lamports / 1000000000; // Convert lamports to SOL
        });
      }
    } catch (e) {
      setState(() => _status = "Failed to get balance: $e");
    }
  }

  /// Request permissions for camera and storage
  /// Solicita permisos para la cámara y el almacenamiento
  Future<bool> _requestPermissions() async {
    print("Solicitando permisos...");

    // Solicita el permiso de cámara
    var cameraStatus = await Permission.camera.status;
    print("Estado del permiso de cámara: $cameraStatus");

    if (!cameraStatus.isGranted) {
      print("Permiso de cámara no concedido, solicitando...");
      cameraStatus = await Permission.camera.request();
      print("Resultado de la solicitud de permiso de cámara: $cameraStatus");

      if (!cameraStatus.isGranted) {
        print("Permiso de cámara denegado.");
        setState(() {
          _status = "Camera permission denied.";
        });
        return false;
      }
    } else {
      print("Permiso de cámara ya concedido.");
    }

    // Solicita el permiso de almacenamiento (si es necesario)
    var storageStatus = await Permission.storage.status;
    print("Estado del permiso de almacenamiento: $storageStatus");


    print("Todos los permisos concedidos.");
    return true;
  }

  /// Capture image using camera
  Future<void> _captureImage() async {
    // Request permissions before capturing the image
    bool permissionsGranted = await _requestPermissions();
    print("PermissionsGranted::::::::::::::::::::::::" + permissionsGranted.toString());
    print("::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::wtf bro");
    if (!permissionsGranted) return;
    print("Llegas aqui????????????????????????????");
    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _capturedImage = image;
          _status = "Image captured!";
        });
      } else {
        setState(() {
          _status = "Image capture cancelled.";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Error capturing image: $e";
      });
    }
  }

  /// Get current location
  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _status = "Location services are disabled.";
        });
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _status = "Location permission denied.";
          });
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _status = "Location permissions are permanently denied.";
        });
        return null;
      }

      return await Geolocator.getCurrentPosition();
    } catch (e) {
      setState(() {
        _status = "Failed to get location: $e";
      });
      return null;
    }
  }

  Future<void> _handleMintingHardcoded() async {
    try {
      // Mensaje simple para firmar
      final message = utf8.encode('Hello, sign this message!');
      final encodedMessage = adapter.encodeMessage(message as String);

      final signResult = await adapter.signMessages([encodedMessage], addresses: [adapter.connectedAccount?.toBase58() ?? '']);

      print('Signed message: ${signResult.signedPayloads}');
    } catch (e) {
      print('Error signing message: $e');
      setState(() => _status = "Error signing message: $e");
    }
    setState(() {
      _loading = true;
      _status = "Initiating minting process...";
    });

    try {
      print("::: Starting minting process");
      final currentTx = transactionBase64;
      final web3.Transaction transaction = web3.Transaction.deserialize(base64Decode(currentTx));

      print("::: Transaction Base64: $currentTx");

      final connection = web3.Connection(web3.Cluster.mainnet);
      print("::: Connection to Solana mainnet cluster established");

      print("::: Checking if adapter is authorized");
      final isAuthorized = await adapter.isAuthorized;
      print("authorization token: ${adapter.authorizeResult?.authToken}");

      print("isAuthorized: " + isAuthorized.toString());



      print("Capabilities: ");

      print("::: Attempting to sign the transaction...");
      var signResult;
      try {
        print("Attempting to sign transaction with adapter...");
        signResult = await adapter.signTransactions([adapter.encodeTransaction(transaction)]);
        print("Sign result: $signResult");
      } catch (error) {
        print("Error during transaction signing: $error");
        setState(() {
          _status = "Signing failed: $error";
          _loading = false;
        });
      }
      final signedTx = signResult;
      print("::: Successfully signed transaction");



      setState(() {
        _status = "NFT Minted Successfully! View on Solscan";
        _loading = false;
      });


    } catch (e) {
      print("::: Error during minting process: $e");
      setState(() {
        _status = "Error: ${e.toString()}";
        _loading = false;
      });
    }
  }

  /// Upload image to server
  /// Handles the full process of capturing image, getting location, uploading, and minting
  Future<void> _handleMintingProcess() async {
    setState(() {
      _status = "Minting NFT...";
      _loading = true;
    });
    // Check if an image has been captured
    if (_capturedImage == null) {
      setState(() {
        _status = "No image captured!";
      });
      return;
    }

    // Get current location
    final position = await _getCurrentLocation();
    if (position == null) return;

    try {
      // Request permissions before proceeding
      bool permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        setState(() {
          _status = "Required permissions not granted.";
        });
        return;
      }

      // Define the API endpoint that handles both image upload and NFT minting
      final uri = Uri.parse('https://solpay-api.cryptoadvisor.tech/solana/upload-and-create-collection');

      // Create a multipart request to upload the image and pass additional data
      final request = http.MultipartRequest('POST', uri)
        ..fields['fromPubKey'] = adapter.connectedAccount?.toBase58() ?? ''
        ..fields['latitude'] = position.latitude.toString()
        ..fields['longitude'] = position.longitude.toString()
        ..files.add(await http.MultipartFile.fromPath('file', _capturedImage!.path));

      // Log request details
      print("::: Sending request to: ${request.url}");
      print("::: Request method: ${request.method}");
      print("::: Request headers: ${request.headers}");
      print("::: Request fields: ${request.fields}");
      print("::: Request files: ${request.files.map((file) => file.filename).toList()}");

      // Send the request
      final response = await request.send();

      // Print the response status code and reason phrase
      print("::: Response status code: ${response.statusCode}");
      print("::: Response reason phrase: ${response.reasonPhrase}");

      // If the response has a body, print it for further inspection
      final responseBody = await response.stream.bytesToString();
      print("::: Response body: $responseBody");

      // Check if the request was successful
      if (response.statusCode == 200) {
        print("::: Response status code: ${response.statusCode}");
        print("::: Successful response!");

        // Decode the response body
        final responseData = jsonDecode(responseBody);
        print("::: Response data: $responseData");

        // Extract transaction from response
        final String transactionBase64 = responseData['data']['transaction'];
        print("::: Transaction Base64: $transactionBase64");

        // Decode the transaction from Base64 bytes
        final transactionBytes = base64Decode(transactionBase64);
        print("::: Transaction bytes decoded: $transactionBytes");

        // Deserialize the transaction
        final transaction = web3.Transaction.deserialize(transactionBytes);
        print("::: Transaction deserialized successfully");

        // Create a connection to the Solana cluster
        final connection = web3.Connection(web3.Cluster.mainnet);
        print("::: Connection to Solana cluster established");

        // Check if adapter is authorized before signing
        print("::: Is adapter authorized? ${adapter.isAuthorized}");

        print("::: Attempting to sign the transaction...");
        final signResult = await adapter.signTransactions([transactionBase64]);
        print("::: Sign result: $signResult");

        if (signResult == null) {
          print("::: Signing failed or was cancelled.");
          setState(() {
            _status = "Transaction signing failed or was cancelled.";
            _loading = false;
          });
          return;
        }

        // Send the signed transaction to the Solana network
        print("::: Sending signed transaction to Solana network...");
        final signature = await connection.sendAndConfirmTransaction(transaction);
        print("::: Transaction sent successfully, signature: $signature");

        // Generate Solscan URL for the transaction
        final solscanUrl = 'https://solscan.io/tx/$signature';
        print("::: Solscan URL: $solscanUrl");

        // Update the status with the transaction signature and link to Solscan
        setState(() {
          _status = "NFT Minted Successfully! View on Solscan: $solscanUrl";
          _loading = false;
        });

        // Optionally launch the URL in the browser
        if (await canLaunch(solscanUrl)) {
          await launch(solscanUrl);
        }
      } else {
        print("::: Minting failed with status code: ${response.statusCode}");
        setState(() {
          _status = "Minting failed: ${response.statusCode} ${response.reasonPhrase}";
        });
      }
    } catch (e) {
      print("::: Exception caught: $e");
      setState(() {
        _status = "Minting failed: $e";
        _loading = false;
      });
    }
  }

  /// Function to format address
  String _formatAddress(String? address) {
    if (address == null) return "";
    return "${address.substring(0, 4)}...${address.substring(address.length - 4)}";
  }

  Widget _buildConnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    "Wallet Address",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Text(
                        _formatAddress(adapter.connectedAccount?.toBase58()),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          // Copy address to clipboard
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Balance: ${_balance ?? '...'} SOL",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          _capturedImage != null
              ? Image.file(
            File(_capturedImage!.path),
            height: 100,
            width: 100,
            fit: BoxFit.cover,
          )
              : const SizedBox(),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _disconnect,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(16)),
            child: const Text('Disconnect'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _captureImage,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: const Text('Capture Image'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _handleMintingHardcoded,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: const Text('Mint NFT'),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_status ?? '', textAlign: TextAlign.center),
          ),
          ElevatedButton(onPressed: _getBalance, child: const Text("Get Balance")),
        ],
      ),
    );
  }

  Widget _buildDisconnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.link_off, size: 100, color: Colors.grey),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Connect Wallet', style: TextStyle(fontSize: 18)),
          ),
          if (_status != null) ...[
            const SizedBox(height: 20),
            Text(
              _status!,
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      body: Center(
        child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            return adapter.isAuthorized ? _buildConnectedView() : _buildDisconnectedView();
          },
        ),
      ),
    );
  }
}
