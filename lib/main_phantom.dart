import 'package:flutter/material.dart';
import 'package:pinenacl/x25519.dart' show Box, PrivateKey, PublicKey;
import 'package:uni_links/uni_links.dart';
import 'dart:async';
import 'dart:convert';
import 'package:pinenacl/api.dart' show ByteList, ByteListExtension, EncryptedMessage, IntListExtension, PineNaClUtils;
import 'package:bs58/bs58.dart' as bs58;
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'package:pinenacl/tweetnacl.dart';

const String appScheme = 'myflutterapp';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Método build permanece igual
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Ejemplo Phantom Flutter',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: PhantomExample());
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

  @override
  void initState() {
    super.initState();
    initUniLinks();
    // Generar dappKeyPair
    dappPrivateKey = PrivateKey.generate();
    dappPublicKey = dappPrivateKey!.publicKey;

    // Agregar logs para verificar las claves generadas
    print('Dapp Private Key: ${dappPrivateKey!.asTypedList}');
    print('Dapp Public Key: ${dappPublicKey!.asTypedList}');
  }

  Future<void> initUniLinks() async {
    // Manejo de enlaces profundos
    try {
      Uri? initialUri = await getInitialUri();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } on Exception catch (e) {
      // Manejar excepciones
      print('Error al obtener initialUri: $e');
    }

    // Escuchar cambios en los enlaces
    _sub = uriLinkStream.listen((Uri? uri) {
      if (!mounted) return;
      if (uri != null) {
        _handleDeepLink(uri);
      }
    }, onError: (Object err) {
      // Manejar errores
      print('Error en uriLinkStream: $err');
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
    // Imprimir el log en la consola para depuración
    print(message);
  }


  void _handleDeepLink(Uri uri) {
    print('Deep Link recibido: $uri');
    setState(() {
      _deepLinkURL = uri.toString();
    });
    // Procesar el URI
    Map<String, String> params = uri.queryParameters;
    print('Parámetros del URI: $params');
    if (params.containsKey('errorCode')) {
      // Manejar errores
      String errorMessage = params['errorMessage'] ?? 'Error desconocido';
      addLog('Error: $errorMessage');
      print('Error recibido en el deep link: $errorMessage');
      return;
    }

    String host = uri.host.toLowerCase();

    if (host == 'onconnect') {
      // Manejar respuesta de conexión
      var phantomEncryptionPublicKey = params['phantom_encryption_public_key'];
      var nonce = params['nonce'];
      var data = params['data'];

      print('phantom_encryption_public_key: $phantomEncryptionPublicKey');
      print('nonce: $nonce');
      print('data: $data');

      if (phantomEncryptionPublicKey != null && nonce != null && data != null) {
        Uint8List phantomPublicKeyBytes = bs58.base58.decode(phantomEncryptionPublicKey);
        PublicKey phantomPubKey = PublicKey(phantomPublicKeyBytes);

        // Crear Box para cifrado/descifrado
        box = Box(myPrivateKey: dappPrivateKey!, theirPublicKey: phantomPubKey);
        print('Box creado: $box');

        // Desencriptar datos
        Map<String, dynamic> decryptedData = decryptPayload(data, nonce);
        print('Datos desencriptados: $decryptedData');

        session = decryptedData['session'];
        phantomPublicKey = decryptedData['public_key'];
        setState(() {
          walletAddress = phantomPublicKey;
        });
        addLog('Conectado. Public Key: $phantomPublicKey');
        addLog('Session: $session');
        addLog('Box: $box');
      } else {
        print('Faltan parámetros para la conexión');
      }
    } else if (host == 'onsigntransaction') {
      // Manejar respuesta de firma de transacción
      var nonce = params['nonce'];
      var data = params['data'];

      print('nonce: $nonce');
      print('data: $data');

      if (nonce != null && data != null) {
        Map<String, dynamic> decryptedData = decryptPayload(data, nonce);
        print('Datos desencriptados de la transacción: $decryptedData');

        var signedTransaction = decryptedData['transaction'];
        addLog('Transacción firmada: $signedTransaction');
        // Aquí puedes manejar la transacción firmada según tus necesidades
      } else {
        print('Faltan parámetros para la firma de transacción');
      }
    } else {
      // Manejar otros métodos si es necesario
      print('Ruta no reconocida en el deep link: ${uri.host}');
    }
  }


  Map<String, dynamic> decryptPayload(String data, String nonce) {
    if (box == null) throw Exception('Box no inicializado');
    Uint8List cipherText = bs58.base58.decode(data);
    Uint8List nonceBytes = bs58.base58.decode(nonce);

    print('Cifrador (box): $box');
    print('CipherText (decodificado): $cipherText');
    print('Nonce (decodificado): $nonceBytes');

    // Crear un EncryptedMessage con el cipherText y el nonce
    EncryptedMessage encryptedMessage = EncryptedMessage(nonce: nonceBytes, cipherText: cipherText);

    // Desencriptar el mensaje y convertir a Uint8List
    Uint8List decrypted = box!.decrypt(encryptedMessage).toUint8List();
    print('Mensaje desencriptado (bytes): $decrypted');

    String jsonString = utf8.decode(decrypted);
    print('Mensaje desencriptado (string JSON): $jsonString');

    return json.decode(jsonString);
  }



  Map<String, Uint8List> encryptPayload(Map<String, dynamic> payload) {
    if (box == null) throw Exception('Box no inicializado');
    Uint8List nonce = PineNaClUtils.randombytes(24);
    Uint8List message = Uint8List.fromList(utf8.encode(json.encode(payload)));

    print('Payload a encriptar: $payload');
    print('Mensaje en bytes: $message');
    print('Nonce generado: $nonce');

    // Encriptar el mensaje
    final encryptedMessage = box!.encrypt(message, nonce: nonce);

    // Convertir el cipherText a Uint8List
    Uint8List encryptedPayload = encryptedMessage.cipherText.toUint8List();

    print('Mensaje encriptado (cipherText): $encryptedPayload');

    return {'nonce': nonce, 'payload': encryptedPayload};
  }



  void connect() async {
    String dappEncryptionPublicKey = bs58.base58.encode(dappPublicKey!.asTypedList);
    String cluster = 'mainnet-beta';
    String appUrl = 'https://phantom.app';
    String redirectLink = '$appScheme://onConnect'; // Utiliza el esquema definido

    Uri url = Uri.https('phantom.app', '/ul/v1/connect', {
      'dapp_encryption_public_key': dappEncryptionPublicKey,
      'cluster': cluster,
      'app_url': appUrl,
      'redirect_link': redirectLink,
    });

    String urlStr = url.toString();
    print('URL para conectar: $urlStr');

    if (await canLaunch(urlStr)) {
      await launch(urlStr);
    } else {
      throw 'No se pudo abrir $urlStr';
    }
  }

  void signTransaction() async {
    String redirectLink = '$appScheme://onSignTransaction'; // Utiliza el esquema definido

    if (session == null || box == null) {
      addLog('Por favor, conéctate primero.');
      print('No se puede firmar la transacción porque session o box es null');
      print('Session: $session');
      print('Box: $box');
      return;
    }
    // Transacción hardcodeada
    String transactionBase64 = "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACKKwj9oxkP6zv0A3Vmv/FfV7c1E9J5gkIDlRHr0vDZ6ZHx28mzJP2YRmi1AnUBgxvSt5qjn3kBJ6Z06zp1ZlwFgAIABQoyyR+rbftBNtRAq1ug/Xr497zQDdKnAw8Rek4+bOsa05ftjiJ8ychmgHiN6gdSHFGSLCzkwFPWLgQxjyS3vnwx/9RAiGIcJ4cf1fr4NfWKD93AI1woL4I31h4Zad/Jxvg1o5TqOXdAaW16G4Lxlt2S/FPn3IFnLCIahHydSmN7LnSnL09bz77/mMJTgO+00ga08HUHfecqsAmN6WG06JgrC3BlsePRfEU4nVJ/awTDzVi4bHMaoP21SbbRvAP4KUYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAan1RcYe9FmNdrUBFX9wsDBJMaPIVZ1pdu6y18IAAAABt324ddloZPZy+FGzut5rBy0he1fWzeROoz1hX7/AKmMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZ1gCCxqe3XEDUm1a9m+sFhtjf+gj6qAAdW2PiOt0bi7AgUJAgMBAAAABgcIvgEqABEAAABNeSBDb2xsZWN0aW9uIE5GVAoAAABTNi1leGFtcGxlWQAAAGh0dHBzOi8vYmxvY2tjaGFpbnN0YXJ0ZXIuc2ZvMy5kaWdpdGFsb2NlYW5zcGFjZXMuY29tL3VwbG9hZHMvbWV0YWRhdGEtMTcyNjA3NjgwNDAwNy5qc29u5wMBAQAAADLJH6tt+0E21ECrW6D9evj3vNAN0qcDDxF6Tj5s6xrTAWQAAQAAAAEAAAAAAAAAAAAAAAEABQ8EAAIDBQEABQAGBwgJBQULKwABAAAAAAAAAAAA";
    // Convertir base64 a bytes
    Uint8List transactionBytes = base64.decode(transactionBase64);
    // Codificar en base58
    String transactionBase58 = bs58.base58.encode(transactionBytes);

    Map<String, dynamic> payload = {
      'session': session,
      'transaction': transactionBase58,
    };

    print('Payload para firmar transacción: $payload');

    Map<String, Uint8List> encrypted = encryptPayload(payload);
    String dappEncryptionPublicKey = bs58.base58.encode(dappPublicKey!.asTypedList);
    String nonceBase58 = bs58.base58.encode(encrypted['nonce']!);
    String payloadBase58 = bs58.base58.encode(encrypted['payload']!);

    print('nonceBase58: $nonceBase58');
    print('payloadBase58: $payloadBase58');

    Uri url = Uri.https('phantom.app', '/ul/v1/signTransaction', {
      'dapp_encryption_public_key': dappEncryptionPublicKey,
      'nonce': nonceBase58,
      'redirect_link': redirectLink,
      'payload': payloadBase58,
    });

    String urlStr = url.toString();
    print('URL para firmar transacción: $urlStr');

    if (await canLaunch(urlStr)) {
      await launch(urlStr);
    } else {
      throw 'No se pudo abrir $urlStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ejemplo Phantom Flutter'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(logs[index]),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: connect,
            child: Text('Conectar a Phantom'),
          ),
          ElevatedButton(
            onPressed: signTransaction,
            child: Text('Firmar Transacción'),
          ),
        ],
      ),
    );
  }
}
