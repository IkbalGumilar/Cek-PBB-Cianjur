/// Data referensi resmi Wilayah Administratif Kabupaten Cianjur (32 Kecamatan).
/// Digunakan untuk pemetaan otomatis kode kecamatan dan kode desa ke dalam NOP Prefix 10 Digit:
/// 32 (Provinsi Jabar) + 05 (Kab. Cianjur) + 3 digit Kecamatan + 3 digit Desa/Kelurahan.
library;

class DesaOption {
  final String code; // 3 digit kode Bapenda, misal '004'
  final String name; // Nama desa, misal 'BOBOJONG'

  const DesaOption({required this.code, required this.name});
}

class KecamatanOption {
  final String code; // 3 digit kode Bapenda, misal '200'
  final String name; // Nama kecamatan, misal 'MANDE'
  final List<DesaOption> desaList;

  const KecamatanOption({
    required this.code,
    required this.name,
    this.desaList = const [],
  });
}

/// Daftar 32 Kecamatan di Kabupaten Cianjur beserta daftar desa dan kode resminya.
/// Diurutkan secara alfabetis (A-Z) berdasarkan nama Kecamatan dan nama Desa.
const List<KecamatanOption> cianjurWilayahCatalog = [
  KecamatanOption(
    code: '010',
    name: 'AGRABINTA',
    desaList: [
      DesaOption(code: '001', name: 'AGRABINTA'),
      DesaOption(code: '002', name: 'BOJONGKASO'),
      DesaOption(code: '003', name: 'BUNISARI'),
      DesaOption(code: '004', name: 'KARANGSARI'),
      DesaOption(code: '005', name: 'MULYASARI'),
      DesaOption(code: '006', name: 'NEGLASARI'),
      DesaOption(code: '007', name: 'SINARLAUT'),
      DesaOption(code: '008', name: 'SUKAMANAH'),
      DesaOption(code: '009', name: 'TANJUNGSARI'),
      DesaOption(code: '010', name: 'WANASARI'),
      DesaOption(code: '011', name: 'WANGUNJAYA'),
    ],
  ),
  KecamatanOption(
    code: '060',
    name: 'BOJONGPICUNG',
    desaList: [
      DesaOption(code: '001', name: 'BOJONGPICUNG'),
      DesaOption(code: '002', name: 'CIBARENGKOK'),
      DesaOption(code: '003', name: 'CIKONDANG'),
      DesaOption(code: '004', name: 'HEGARMANAH'),
      DesaOption(code: '005', name: 'JATI'),
      DesaOption(code: '006', name: 'JATISARI'),
      DesaOption(code: '007', name: 'KEMANG'),
      DesaOption(code: '008', name: 'NEGLASARI'),
      DesaOption(code: '009', name: 'SUKAJATU'),
      DesaOption(code: '010', name: 'SUKARAMA'),
    ],
  ),
  KecamatanOption(
    code: '150',
    name: 'CAMPAKA',
    desaList: [
      DesaOption(code: '001', name: 'CAMPAKA'),
      DesaOption(code: '002', name: 'CIDADAP'),
      DesaOption(code: '003', name: 'CIMENTENG'),
      DesaOption(code: '004', name: 'GIRIMUKTI'),
      DesaOption(code: '005', name: 'KARYAMUKTI'),
      DesaOption(code: '006', name: 'MARGALUYU'),
      DesaOption(code: '007', name: 'MEKARJAYA'),
      DesaOption(code: '008', name: 'SUKADANA'),
      DesaOption(code: '009', name: 'SUKAJADI'),
      DesaOption(code: '010', name: 'SUSUKAN'),
      DesaOption(code: '011', name: 'WANGUNJAYA'),
    ],
  ),
  KecamatanOption(
    code: '250',
    name: 'CAMPAKAMULYA',
    desaList: [
      DesaOption(code: '001', name: 'CAMPAKAMEKAR'),
      DesaOption(code: '002', name: 'CAMPAKAMULYA'),
      DesaOption(code: '003', name: 'CIBANGGALA'),
      DesaOption(code: '004', name: 'SUKABUNGAH'),
      DesaOption(code: '005', name: 'SUKASIRNA'),
    ],
  ),
  KecamatanOption(
    code: '011',
    name: 'CIANJUR',
    desaList: [
      DesaOption(code: '001', name: 'BABAKANKARET'),
      DesaOption(code: '002', name: 'BOJONGHERANG'),
      DesaOption(code: '003', name: 'LIMBANGANSARI'),
      DesaOption(code: '004', name: 'MEKARSARI'),
      DesaOption(code: '005', name: 'MUKA'),
      DesaOption(code: '006', name: 'NAGRAK'),
      DesaOption(code: '007', name: 'PAMOYANAN'),
      DesaOption(code: '008', name: 'SAWAH GEDE'),
      DesaOption(code: '009', name: 'SAYANG'),
      DesaOption(code: '010', name: 'SOLOKPANDAN'),
      DesaOption(code: '011', name: 'SUKAMAJU'),
    ],
  ),
  KecamatanOption(
    code: '030',
    name: 'CIBEBER',
    desaList: [
      DesaOption(code: '001', name: 'CIHAUR'),
      DesaOption(code: '002', name: 'CIKONDANG'),
      DesaOption(code: '003', name: 'CIMANGGU'),
      DesaOption(code: '004', name: 'CIPETIR'),
      DesaOption(code: '005', name: 'CISALAK'),
      DesaOption(code: '006', name: 'GIRIMULYA'),
      DesaOption(code: '007', name: 'KANOMAN'),
      DesaOption(code: '008', name: 'MAYAK'),
      DesaOption(code: '009', name: 'PEUTEUYCONDONG'),
      DesaOption(code: '010', name: 'SALAMNUNGGAL'),
      DesaOption(code: '011', name: 'SUKAMAJU'),
      DesaOption(code: '012', name: 'SUKAMANAH'),
      DesaOption(code: '013', name: 'SUKARAHARJA'),
    ],
  ),
  KecamatanOption(
    code: '201',
    name: 'CIBINONG',
    desaList: [
      DesaOption(code: '001', name: 'BATULAWANG'),
      DesaOption(code: '002', name: 'CIBURIAL'),
      DesaOption(code: '003', name: 'CIKUNING'),
      DesaOption(code: '004', name: 'CIMASKARA'),
      DesaOption(code: '005', name: 'HAMERANG'),
      DesaOption(code: '006', name: 'MEKARMUKTI'),
      DesaOption(code: '007', name: 'PADASUKA'),
      DesaOption(code: '008', name: 'PAMOYANAN'),
      DesaOption(code: '009', name: 'PANANGGAPAN'),
      DesaOption(code: '010', name: 'PANYINDANGAN'),
      DesaOption(code: '011', name: 'SUKAJADI'),
      DesaOption(code: '013', name: 'SUKAMAJU'),
      DesaOption(code: '012', name: 'SUKAMEKAR'),
      DesaOption(code: '014', name: 'WASPADA'),
    ],
  ),
  KecamatanOption(
    code: '230',
    name: 'CIDAUN',
    desaList: [
      DesaOption(code: '001', name: 'CIBULUH'),
      DesaOption(code: '002', name: 'CIDAMAR'),
      DesaOption(code: '003', name: 'CIMARAGANG'),
      DesaOption(code: '004', name: 'CISARANTEN'),
      DesaOption(code: '005', name: 'KARANGWANGI'),
      DesaOption(code: '006', name: 'KARYABAKTI'),
      DesaOption(code: '007', name: 'KERTAJAYA'),
      DesaOption(code: '008', name: 'NEGLASARI'),
      DesaOption(code: '009', name: 'PUNCAKBARU'),
      DesaOption(code: '010', name: 'PURWALAHIR'),
      DesaOption(code: '011', name: 'SUKAPURA'),
      DesaOption(code: '012', name: 'TANJUNGSARI'),
    ],
  ),
  KecamatanOption(
    code: '290',
    name: 'CIJATI',
    desaList: [
      DesaOption(code: '001', name: 'BOJONGLARANG'),
      DesaOption(code: '002', name: 'CARIGI'),
      DesaOption(code: '003', name: 'CIBODAS'),
      DesaOption(code: '004', name: 'CIJATI'),
      DesaOption(code: '005', name: 'CIKANCANA'),
      DesaOption(code: '006', name: 'PADAASIH'),
      DesaOption(code: '007', name: 'PARAKANTUGU'),
      DesaOption(code: '008', name: 'PASIRNANGKA'),
      DesaOption(code: '009', name: 'SUKAMAHI'),
      DesaOption(code: '010', name: 'SUKAMAJU'),
    ],
  ),
  KecamatanOption(
    code: '260',
    name: 'CIKADU',
    desaList: [
      DesaOption(code: '001', name: 'CIKADU'),
      DesaOption(code: '002', name: 'CISARANTEN'),
      DesaOption(code: '003', name: 'KALAPANUNGGAL'),
      DesaOption(code: '004', name: 'MEKARLAKSANA'),
      DesaOption(code: '005', name: 'MEKARMULYA'),
      DesaOption(code: '006', name: 'MEKARSARI'),
      DesaOption(code: '007', name: 'PADALUYU'),
      DesaOption(code: '008', name: 'SUKALUYU'),
      DesaOption(code: '009', name: 'SUKAMULYA'),
      DesaOption(code: '010', name: 'SUKARESMI'),
    ],
  ),
  KecamatanOption(
    code: '120',
    name: 'CIKALONGKULON',
    desaList: [
      DesaOption(code: '001', name: 'CIGUNUNGHERANG'),
      DesaOption(code: '002', name: 'CIJAGANG'),
      DesaOption(code: '003', name: 'CINANGSI'),
      DesaOption(code: '004', name: 'CIRAMAGIRANG'),
      DesaOption(code: '005', name: 'GUDANG'),
      DesaOption(code: '006', name: 'KAMURANG'),
      DesaOption(code: '007', name: 'LEMBAHSARI'),
      DesaOption(code: '008', name: 'MAJALAYA'),
      DesaOption(code: '009', name: 'MEKARGALIH'),
      DesaOption(code: '010', name: 'MEKARMULYA'),
      DesaOption(code: '011', name: 'MEKARSARI'),
      DesaOption(code: '012', name: 'NEGLASARI'),
      DesaOption(code: '013', name: 'PADAJAYA'),
      DesaOption(code: '014', name: 'SUKAGALIH'),
      DesaOption(code: '015', name: 'SUKAMULYA'),
      DesaOption(code: '016', name: 'WARUDOYONG'),
    ],
  ),
  KecamatanOption(
    code: '040',
    name: 'CILAKU',
    desaList: [
      DesaOption(code: '001', name: 'CIBINONGHILIR'),
      DesaOption(code: '002', name: 'CIHARASHAS'),
      DesaOption(code: '003', name: 'MULYASARI'),
      DesaOption(code: '004', name: 'MUNJUL'),
      DesaOption(code: '005', name: 'RAHONG'),
      DesaOption(code: '006', name: 'RANCAGOONG'),
      DesaOption(code: '007', name: 'SINDANGSARI'),
      DesaOption(code: '008', name: 'SIRNAGALIH'),
      DesaOption(code: '009', name: 'SUKAKERTA'),
      DesaOption(code: '010', name: 'SUKASARI'),
    ],
  ),
  KecamatanOption(
    code: '280',
    name: 'CIPANAS',
    desaList: [
      DesaOption(code: '001', name: 'BATULAWANG'),
      DesaOption(code: '002', name: 'CILOTO'),
      DesaOption(code: '003', name: 'CIMACAN'),
      DesaOption(code: '004', name: 'CIPANAS'),
      DesaOption(code: '005', name: 'GADOG'),
      DesaOption(code: '006', name: 'PALASARI'),
      DesaOption(code: '007', name: 'SINDANGJAYA'),
    ],
  ),
  KecamatanOption(
    code: '050',
    name: 'CIRANJANG',
    desaList: [
      DesaOption(code: '001', name: 'CIBIUK'),
      DesaOption(code: '002', name: 'CIRANJANG'),
      DesaOption(code: '003', name: 'GUNUNGSARI'),
      DesaOption(code: '004', name: 'KARANGWANGI'),
      DesaOption(code: '005', name: 'KERTAJAYA'),
      DesaOption(code: '006', name: 'MEKARGALIH'),
      DesaOption(code: '007', name: 'NANGGALAMEKAR'),
      DesaOption(code: '008', name: 'SINDANGJAYA'),
      DesaOption(code: '009', name: 'SINDANGSARI'),
    ],
  ),
  KecamatanOption(
    code: '330',
    name: 'CUGENANG',
    desaList: [
      DesaOption(code: '001', name: 'BENJOT'),
      DesaOption(code: '002', name: 'CIBULAKAN'),
      DesaOption(code: '003', name: 'CIJEDIL'),
      DesaOption(code: '004', name: 'CIRUMPUT'),
      DesaOption(code: '005', name: 'GASOL'),
      DesaOption(code: '006', name: 'MANGUNKERTA'),
      DesaOption(code: '007', name: 'NYALINDUNG'),
      DesaOption(code: '008', name: 'PADALUYU'),
      DesaOption(code: '009', name: 'SARAMPAD'),
      DesaOption(code: '010', name: 'SUKAMANAH'),
      DesaOption(code: '011', name: 'SUKAMULYA'),
      DesaOption(code: '012', name: 'TALAGA'),
      DesaOption(code: '013', name: 'WANGUNJAYA'),
    ],
  ),
  KecamatanOption(
    code: '310',
    name: 'GEKBRONG',
    desaList: [
      DesaOption(code: '001', name: 'BANGBAYANG'),
      DesaOption(code: '002', name: 'CIKAHURIPAN'),
      DesaOption(code: '003', name: 'CIKANCANA'),
      DesaOption(code: '004', name: 'CINTAASIH'),
      DesaOption(code: '005', name: 'GEKBRONG'),
      DesaOption(code: '006', name: 'KEBONPEUTEUY'),
      DesaOption(code: '007', name: 'SONGGOM'),
      DesaOption(code: '008', name: 'SUKARATU'),
    ],
  ),
  KecamatanOption(
    code: '300',
    name: 'HAURWANGI',
    desaList: [
      DesaOption(code: '001', name: 'CIHEA'),
      DesaOption(code: '002', name: 'CIPEUYEUM'),
      DesaOption(code: '003', name: 'HAURWANGI'),
      DesaOption(code: '004', name: 'KERTAMUKTI'),
      DesaOption(code: '005', name: 'KERTASARI'),
      DesaOption(code: '006', name: 'MEKARWANGI'),
      DesaOption(code: '007', name: 'RAMASARI'),
      DesaOption(code: '008', name: 'SUKATANI'),
    ],
  ),
  KecamatanOption(
    code: '180',
    name: 'KADUPANDAK',
    desaList: [
      DesaOption(code: '001', name: 'BOJONGKASIH'),
      DesaOption(code: '002', name: 'GANDASARI'),
      DesaOption(code: '003', name: 'KADUPANDAK'),
      DesaOption(code: '004', name: 'NEGLASARI'),
      DesaOption(code: '005', name: 'PASIRDALEM'),
      DesaOption(code: '006', name: 'SINDANGSARI'),
      DesaOption(code: '007', name: 'SUKAKERTA'),
      DesaOption(code: '008', name: 'SUKAMAHI'),
      DesaOption(code: '009', name: 'SUKAPURA'),
      DesaOption(code: '010', name: 'SUKARAHARJA'),
      DesaOption(code: '011', name: 'SUKARESMI'),
      DesaOption(code: '012', name: 'SUKASARI'),
      DesaOption(code: '013', name: 'WARGASARI'),
    ],
  ),
  KecamatanOption(
    code: '070',
    name: 'KARANGTENGAH',
    desaList: [
      DesaOption(code: '001', name: 'BABAKANCARINGIN'),
      DesaOption(code: '002', name: 'BOJONG'),
      DesaOption(code: '003', name: 'CIHERANG'),
      DesaOption(code: '004', name: 'HEGARMANAH'),
      DesaOption(code: '005', name: 'MALEBER'),
      DesaOption(code: '006', name: 'SABANDAR'),
      DesaOption(code: '007', name: 'SINDANGASIH'),
      DesaOption(code: '008', name: 'SUKAJADI'),
      DesaOption(code: '009', name: 'SUKAMANAH'),
      DesaOption(code: '010', name: 'SUKAMANTRI'),
      DesaOption(code: '011', name: 'SUKAMULYA'),
      DesaOption(code: '012', name: 'SUKASARANA'),
      DesaOption(code: '013', name: 'SUKATARIS'),
    ],
  ),
  KecamatanOption(
    code: '350',
    name: 'LELES',
    desaList: [
      DesaOption(code: '001', name: 'KARYAMUKTI'),
      DesaOption(code: '002', name: 'MANDALAWANGI'),
      DesaOption(code: '003', name: 'NAGASARI'),
      DesaOption(code: '004', name: 'PUNCAKWANGI'),
      DesaOption(code: '005', name: 'PURABAYA'),
      DesaOption(code: '006', name: 'PUSAKASARI'),
      DesaOption(code: '007', name: 'SIMPARSARI'),
      DesaOption(code: '008', name: 'SINARMULYA'),
      DesaOption(code: '009', name: 'SIRNASARI'),
      DesaOption(code: '010', name: 'SUKAJAYA'),
      DesaOption(code: '011', name: 'SUKAMULYA'),
      DesaOption(code: '012', name: 'WALAHIR'),
    ],
  ),
  KecamatanOption(
    code: '200',
    name: 'MANDE',
    desaList: [
      DesaOption(code: '004', name: 'BOBOJONG'),
      DesaOption(code: '010', name: 'CIANDAM'),
      DesaOption(code: '005', name: 'CIKIDANGBAYABANG'),
      DesaOption(code: '009', name: 'JAMALI'),
      DesaOption(code: '003', name: 'KADEMANGAN'),
      DesaOption(code: '011', name: 'KUTAWARINGIN'),
      DesaOption(code: '012', name: 'LEUWIKOJA'),
      DesaOption(code: '006', name: 'MANDE'),
      DesaOption(code: '001', name: 'MEKARJAYA'),
      DesaOption(code: '008', name: 'MULYASARI'),
      DesaOption(code: '007', name: 'MURNISARI'),
      DesaOption(code: '002', name: 'SUKAMANAH'),
    ],
  ),
  KecamatanOption(
    code: '270',
    name: 'NARINGGUL',
    desaList: [
      DesaOption(code: '001', name: 'BALEGEDE'),
      DesaOption(code: '002', name: 'CINERANG'),
      DesaOption(code: '003', name: 'MALATI'),
      DesaOption(code: '004', name: 'MARGASARI'),
      DesaOption(code: '005', name: 'NARINGGUL'),
      DesaOption(code: '006', name: 'SUKABUMI'),
      DesaOption(code: '007', name: 'SUKAMULYA'),
      DesaOption(code: '008', name: 'WANASARI'),
      DesaOption(code: '009', name: 'WANGUNJAYA'),
      DesaOption(code: '010', name: 'WANGUNSARI'),
    ],
  ),
  KecamatanOption(
    code: '140',
    name: 'PACET',
    desaList: [
      DesaOption(code: '001', name: 'CIBODAS'),
      DesaOption(code: '002', name: 'CIHERANG'),
      DesaOption(code: '003', name: 'CIPENDAWA'),
      DesaOption(code: '004', name: 'GADOG'),
      DesaOption(code: '005', name: 'SUKANAGALIH'),
      DesaOption(code: '006', name: 'SUKATANI'),
    ],
  ),
  KecamatanOption(
    code: '190',
    name: 'PAGELARAN',
    desaList: [
      DesaOption(code: '001', name: 'BUNIJAYA'),
      DesaOption(code: '002', name: 'BUNIWANGI'),
      DesaOption(code: '003', name: 'GELARPAWITAN'),
      DesaOption(code: '004', name: 'KARANGHARJA'),
      DesaOption(code: '005', name: 'KERTARAHARJA'),
      DesaOption(code: '006', name: 'MEKARSARI'),
      DesaOption(code: '007', name: 'PADAMAJU'),
      DesaOption(code: '008', name: 'PAGELARAN'),
      DesaOption(code: '009', name: 'PANGADEGAN'),
      DesaOption(code: '010', name: 'PASIRBARU'),
      DesaOption(code: '011', name: 'SELAGEDANG'),
      DesaOption(code: '012', name: 'SINDANGKERTA'),
      DesaOption(code: '013', name: 'SUKAMAJU'),
      DesaOption(code: '014', name: 'SUKARESMI'),
    ],
  ),
  KecamatanOption(
    code: '320',
    name: 'PASIRKUDA',
    desaList: [
      DesaOption(code: '001', name: 'ARILELAH'),
      DesaOption(code: '002', name: 'GIRIJAYA'),
      DesaOption(code: '003', name: 'KALI BARU'),
      DesaOption(code: '004', name: 'KARANGJAYA'),
      DesaOption(code: '005', name: 'KUBANG'),
      DesaOption(code: '006', name: 'PADAMULYA'),
      DesaOption(code: '007', name: 'PUSAKAJAYA'),
      DesaOption(code: '008', name: 'SIMPANG'),
      DesaOption(code: '009', name: 'SUGIHMUKTI'),
    ],
  ),
  KecamatanOption(
    code: '210',
    name: 'SINDANGBARANG',
    desaList: [
      DesaOption(code: '001', name: 'BOJONGHAUR'),
      DesaOption(code: '002', name: 'GIRIMUKTI'),
      DesaOption(code: '003', name: 'HEGARSARI'),
      DesaOption(code: '004', name: 'JATISARI'),
      DesaOption(code: '005', name: 'JAYAGIRI'),
      DesaOption(code: '006', name: 'KARYABAKTI'),
      DesaOption(code: '007', name: 'KARYASARI'),
      DesaOption(code: '008', name: 'MEKARLAKSANA'),
      DesaOption(code: '009', name: 'MUARACIKADU'),
      DesaOption(code: '010', name: 'SAGANTEN'),
      DesaOption(code: '011', name: 'SIRNAGALIH'),
      DesaOption(code: '012', name: 'TALAGASARI'),
    ],
  ),
  KecamatanOption(
    code: '130',
    name: 'SUKALUYU',
    desaList: [
      DesaOption(code: '001', name: 'BABAKANSARI'),
      DesaOption(code: '002', name: 'HEGARMANAH'),
      DesaOption(code: '003', name: 'PANYUSUHAN'),
      DesaOption(code: '004', name: 'SELAJAMBE'),
      DesaOption(code: '005', name: 'SINDANGRAJA'),
      DesaOption(code: '006', name: 'SUKALUYU'),
      DesaOption(code: '007', name: 'SUKAMULYA'),
      DesaOption(code: '008', name: 'SUKASIRNA'),
      DesaOption(code: '009', name: 'TANJUNGSARI'),
    ],
  ),
  KecamatanOption(
    code: '160',
    name: 'SUKANAGARA',
    desaList: [
      DesaOption(code: '001', name: 'CIGUHA'),
      DesaOption(code: '002', name: 'GUNUNGSARI'),
      DesaOption(code: '003', name: 'JAYAGIRI'),
      DesaOption(code: '004', name: 'SIMPANG'),
      DesaOption(code: '005', name: 'SUKAKARYA'),
      DesaOption(code: '006', name: 'SUKALAKSANA'),
      DesaOption(code: '007', name: 'SUKAMEKAR'),
      DesaOption(code: '008', name: 'SUKANAGARA'),
      DesaOption(code: '009', name: 'SUKARAME'),
      DesaOption(code: '010', name: 'SUKARATU'),
    ],
  ),
  KecamatanOption(
    code: '340',
    name: 'SUKARESMI',
    desaList: [
      DesaOption(code: '001', name: 'CIBADAK'),
      DesaOption(code: '002', name: 'CIKANCANA'),
      DesaOption(code: '003', name: 'CIKANYERE'),
      DesaOption(code: '004', name: 'CIWALEN'),
      DesaOption(code: '005', name: 'KAWUNGLUWUK'),
      DesaOption(code: '006', name: 'KUBANG'),
      DesaOption(code: '007', name: 'PAKUON'),
      DesaOption(code: '008', name: 'RAWABELUT'),
      DesaOption(code: '009', name: 'SUKAMAHI'),
      DesaOption(code: '010', name: 'SUKARESMI'),
    ],
  ),
  KecamatanOption(
    code: '170',
    name: 'TAKOKAK',
    desaList: [
      DesaOption(code: '001', name: 'BUNGBANGSARI'),
      DesaOption(code: '002', name: 'CISUJEN'),
      DesaOption(code: '003', name: 'HEGARMANAH'),
      DesaOption(code: '004', name: 'PASASAHAN'),
      DesaOption(code: '005', name: 'SIMPANG'),
      DesaOption(code: '006', name: 'SINDANGRESMI'),
      DesaOption(code: '007', name: 'SUKAGALIH'),
      DesaOption(code: '008', name: 'WARINGINSARI'),
    ],
  ),
  KecamatanOption(
    code: '240',
    name: 'TANGGEUNG',
    desaList: [
      DesaOption(code: '001', name: 'BOJONGPETIR'),
      DesaOption(code: '002', name: 'CILONGKEANG'),
      DesaOption(code: '003', name: 'KERTAJAYA'),
      DesaOption(code: '004', name: 'MARGALUYU'),
      DesaOption(code: '005', name: 'PADALUYU'),
      DesaOption(code: '006', name: 'PASIRJAMBU'),
      DesaOption(code: '007', name: 'RAWAGEDE'),
      DesaOption(code: '008', name: 'SIRNAJAYA'),
      DesaOption(code: '009', name: 'SUKAJAYA'),
      DesaOption(code: '010', name: 'TANGGEUNG'),
    ],
  ),
  KecamatanOption(
    code: '020',
    name: 'WARUNGKONDANG',
    desaList: [
      DesaOption(code: '001', name: 'BUNIKASIH'),
      DesaOption(code: '002', name: 'BUNISARI'),
      DesaOption(code: '003', name: 'CIEUNDEUR'),
      DesaOption(code: '004', name: 'CIKAHURIPAN'),
      DesaOption(code: '005', name: 'CISARANDI'),
      DesaOption(code: '006', name: 'CIWALEN'),
      DesaOption(code: '007', name: 'JAMBUDIPA'),
      DesaOption(code: '008', name: 'MEKARWANGI'),
      DesaOption(code: '009', name: 'SUKAMULYA'),
      DesaOption(code: '010', name: 'SUKAWANGI'),
      DesaOption(code: '011', name: 'TEGALLEGA'),
    ],
  ),
];

/// Helper pencarian opsi kecamatan berdasarkan kode 3 digit.
KecamatanOption? findKecamatanByCode(String code) {
  final clean = code.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  for (final kec in cianjurWilayahCatalog) {
    if (kec.code == clean) return kec;
  }
  return null;
}

/// Helper pencarian nama kecamatan.
String lookupCatalogKecamatanName(String code) {
  return findKecamatanByCode(code)?.name ?? 'Kecamatan ';
}

/// Helper pencarian opsi desa berdasarkan kode kecamatan & kode desa.
DesaOption? findDesaByCode(String kecCode, String desaCode) {
  final kec = findKecamatanByCode(kecCode);
  if (kec == null) return null;
  final cleanDesa = desaCode.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  for (final desa in kec.desaList) {
    if (desa.code == cleanDesa) return desa;
  }
  return null;
}

/// Helper pencarian nama desa.
String lookupCatalogDesaName(String kecCode, String desaCode) {
  return findDesaByCode(kecCode, desaCode)?.name ?? 'Desa $desaCode';
}

/// Hitung prefix NOP 10 digit (3205 + kecCode + desaCode).
String calculateNopPrefix(String kecCode, String desaCode) {
  final cleanKec = kecCode.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  final cleanDesa = desaCode.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  return '3205$cleanKec$cleanDesa';
}
