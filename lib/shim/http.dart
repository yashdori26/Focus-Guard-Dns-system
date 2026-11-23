// Offline stand-in for package:http. Frontend-only build: no network.
import 'dart:convert';
import 'dart:typed_data';

class Response {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  Response(this.body, this.statusCode, {this.headers = const {}});
  Uint8List get bodyBytes => Uint8List.fromList(utf8.encode(body));
}

class Client {
  Future<Response> get(Uri url, {Map<String, String>? headers}) => _off();
  Future<Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
  Future<Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
  Future<Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
  Future<Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
  Future<Response> head(Uri url, {Map<String, String>? headers}) => _off();
  void close() {}
}

Future<Response> _off() => Future.error(Exception('Offline: frontend-only build'));
Future<Response> get(Uri url, {Map<String, String>? headers}) => _off();
Future<Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
Future<Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
Future<Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
Future<Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) => _off();
Future<Response> head(Uri url, {Map<String, String>? headers}) => _off();
