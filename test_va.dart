import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  try {
    final response = await dio.post<String>(
      'https://cektagihan.cianjurkab.v-tax.id/svcGenerateVA.php',
      data: {
        'modul': 'pbb',
        'kdbayar': '320502000500100010',
        'tahun': '2026',
        'area': '3205',
        'tax_type': '2',
        'payment_code': '123456',
        'email': '',
        'telp': '',
        'kode_bank': '3202110',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    print("RESPONSE: ${response.data}");
  } catch (e) {
    print("ERROR: $e");
    if (e is DioException) {
      print("RESPONSE: ${e.response?.data}");
    }
  }
}
