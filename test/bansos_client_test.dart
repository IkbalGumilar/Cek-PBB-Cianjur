import 'package:flutter_test/flutter_test.dart';
import 'package:cek_pbb_app/desil/bansos_client.dart';

void main() {
  group('BansosResult.fromHtml (cb-v4 & legacy compatibility)', () {
    test('parses new cb-v4 /hasil-nik profile and program cards', () {
      const html = '''
      <div class="cb-v4">
        <section class="cb-hero">
          <div class="cb-wrap cb-hero-inner">
            <div>
              <span class="cb-chip">Periode DTSEN: Februari 2026</span>
              <h1 class="cb-title">Hasil Pencarian Data</h1>
            </div>
          </div>
        </section>
        <div class="cb-wrap">
          <section class="cb-result">
            <div class="cb-card cb-profile">
              <div class="cb-profile-main">
                <div class="cb-avatar"><i class="icon-user"></i></div>
                <div>
                  <div class="cb-kicker">Nama Penerima Manfaat</div>
                  <div class="cb-name">ASEP SURYANA</div>
                </div>
              </div>
              <div class="cb-profile-stats">
                <div class="cb-stat cb-stat-desil">
                  <div class="cb-kicker">Desil</div>
                  <div class="cb-desil">2</div>
                </div>
                <div class="cb-stat">
                  <div class="cb-kicker">Keterangan PBI</div>
                  <div class="cb-stat-value">Aktif</div>
                </div>
                <div class="cb-stat">
                  <div class="cb-kicker">Status KPD</div>
                  <div class="cb-stat-value">Tidak Terdaftar</div>
                </div>
              </div>
            </div>
            <div class="cb-programs">
              <div class="cb-card cb-program">
                <div class="cb-program-head"><h3>Sembako</h3></div>
                <dl class="cb-dl">
                  <div><dt>Status</dt><dd>YA</dd></div>
                  <div><dt>Periode</dt><dd>Jan - Mar 2026</dd></div>
                </dl>
              </div>
              <div class="cb-card cb-program">
                <div class="cb-program-head"><h3>PKH</h3></div>
                <dl class="cb-dl">
                  <div><dt>Status</dt><dd>TIDAK</dd></div>
                  <div><dt>Periode</dt><dd>-</dd></div>
                </dl>
              </div>
              <div class="cb-card cb-program">
                <div class="cb-program-head"><h3>PBI-JK</h3></div>
                <dl class="cb-dl">
                  <div><dt>Status</dt><dd>YA</dd></div>
                  <div><dt>Periode</dt><dd>Februari 2026</dd></div>
                </dl>
              </div>
            </div>
          </section>
        </div>
      </div>
      ''';

      final res = BansosResult.fromHtml(html);
      expect(res.periodeDtsen, 'Periode DTSEN: Februari 2026');
      expect(res.nama, 'ASEP SURYANA');
      expect(res.desil, '2');
      expect(res.sembakoStatus, 'YA');
      expect(res.sembakoPeriode, 'Jan - Mar 2026');
      expect(res.pkhStatus, 'TIDAK');
      expect(res.pkhPeriode, '—');
      expect(res.pbiJkStatus, 'YA');
      expect(res.pbiJkPeriode, 'Februari 2026');
      expect(res.keteranganPbi, 'Aktif');
      expect(res.statusKpd, 'Tidak Terdaftar');
    });

    test('detects .cb-empty on /hasil-nik as BansosErrorKind.notFound', () {
      const html = '''
      <div class="cb-v4">
        <section class="cb-result">
          <div class="cb-card cb-empty">
            <span class="cb-empty-icon"><i class="icon-search4"></i></span>
            <p>Data tidak ditemukan</p>
          </div>
        </section>
      </div>
      ''';

      expect(
        () => BansosResult.fromHtml(html),
        throwsA(
          isA<BansosException>().having(
            (e) => e.kind,
            'kind',
            BansosErrorKind.notFound,
          ),
        ),
      );
    });

    test('detects .cb-alert Kode Captcha salah as BansosErrorKind.captcha', () {
      const html = '''
      <div class="cb-v4">
        <div class="cb-search">
          <div class="cb-alert" role="alert">
            <div><span class="font-weight-semibold">Pesan:</span> Kode Captcha salah</div>
          </div>
          <form method="POST" action="https://cekbansos.kemensos.go.id/cekbansos_nik">
            <label for="captcha" class="cb-label">Huruf Kode</label>
          </form>
        </div>
      </div>
      ''';

      expect(
        () => BansosResult.fromHtml(html),
        throwsA(
          isA<BansosException>().having(
            (e) => e.kind,
            'kind',
            BansosErrorKind.captcha,
          ),
        ),
      );
    });
  });
}
