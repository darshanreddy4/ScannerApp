import 'package:xml/xml.dart';

class InvoiceParty {
  const InvoiceParty({this.name = '', this.vatId = '', this.street = '', this.postcode = '', this.city = '', this.country = '', this.email = ''});
  final String name;
  final String vatId;
  final String street;
  final String postcode;
  final String city;
  final String country;
  final String email;

  bool get isEmpty => name.isEmpty && vatId.isEmpty && street.isEmpty && city.isEmpty;

  /// The postal address in one line.
  String get address => [
    street,
    [postcode, city].where((s) => s.isNotEmpty).join(' '),
    country,
  ].where((s) => s.isNotEmpty).join(', ');
}

class InvoiceLine {
  const InvoiceLine({this.name = '', this.quantity = '', this.unit = '', this.unitPrice = '', this.total = '', this.vatRate = ''});
  final String name;
  final String quantity;
  final String unit;
  final String unitPrice;
  final String total;
  final String vatRate;
}

/// An electronic invoice read from its XML: the same few things whatever the format.
class EInvoice {
  const EInvoice({
    required this.format,
    this.isCreditNote = false,
    this.number = '',
    this.issueDate,
    this.dueDate,
    this.currency = '',
    this.seller = const InvoiceParty(),
    this.buyer = const InvoiceParty(),
    this.lines = const [],
    this.netTotal = '',
    this.taxTotal = '',
    this.grandTotal = '',
    this.amountDue = '',
    this.iban = '',
    this.bic = '',
    this.paymentReference = '',
    this.notes = const [],
  });

  /// Which standard it follows, such as `Factur-X / ZUGFeRD` or `FatturaPA`.
  final String format;
  final bool isCreditNote;
  final String number;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final String currency;
  final InvoiceParty seller;
  final InvoiceParty buyer;
  final List<InvoiceLine> lines;
  final String netTotal;
  final String taxTotal;
  final String grandTotal;
  final String amountDue;
  final String iban;
  final String bic;
  final String paymentReference;
  final List<String> notes;

  /// What is to be paid: the amount due, or the total when no amount due is given.
  String get payable => amountDue.isNotEmpty ? amountDue : grandTotal;
}

XmlElement? _c(XmlElement? e, String name) {
  if (e == null) return null;
  for (final c in e.childElements) {
    if (c.name.local == name) return c;
  }
  return null;
}

Iterable<XmlElement> _cs(XmlElement? e, String name) => e == null ? const [] : e.childElements.where((c) => c.name.local == name);

XmlElement? _p(XmlElement? e, String path) {
  var cur = e;
  for (final part in path.split('/')) {
    cur = _c(cur, part);
    if (cur == null) return null;
  }
  return cur;
}

String _t(XmlElement? e, String path) => _p(e, path)?.innerText.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';

DateTime? _date(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 8) return null;
  final y = int.parse(digits.substring(0, 4)), m = int.parse(digits.substring(4, 6)), d = int.parse(digits.substring(6, 8));
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// Reads an electronic invoice: Factur-X / ZUGFeRD and XRechnung (UN/CEFACT CII), XRechnung and Peppol (UBL) or the Italian FatturaPA.
/// Returns null when the XML is none of these.
EInvoice? parseEInvoiceXml(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml.startsWith('\uFEFF') ? xml.substring(1) : xml);
  } on XmlException {
    return null;
  }
  final root = doc.rootElement;
  return switch (root.name.local) {
    'CrossIndustryInvoice' => _cii(root),
    'Invoice' || 'CreditNote' => _ubl(root),
    'FatturaElettronica' => _fattura(root),
    _ => null,
  };
}

InvoiceParty _ciiParty(XmlElement? p) => InvoiceParty(
  name: _t(p, 'Name'),
  vatId:
      [
        for (final r in _cs(p, 'SpecifiedTaxRegistration'))
          if (_c(r, 'ID')?.getAttribute('schemeID') == 'VA') _t(r, 'ID'),
      ].firstOrNull ??
      '',
  street: _t(p, 'PostalTradeAddress/LineOne'),
  postcode: _t(p, 'PostalTradeAddress/PostcodeCode'),
  city: _t(p, 'PostalTradeAddress/CityName'),
  country: _t(p, 'PostalTradeAddress/CountryID'),
  email: _t(p, 'URIUniversalCommunication/URIID'),
);

EInvoice _cii(XmlElement root) {
  final guideline = _t(root, 'ExchangedDocumentContext/GuidelineSpecifiedDocumentContextParameter/ID').toLowerCase();
  final format = guideline.contains('xrechnung')
      ? 'XRechnung (CII)'
      : (guideline.contains('factur-x') || guideline.contains('zugferd') || guideline.contains('facturx'))
      ? 'Factur-X / ZUGFeRD'
      : 'EN 16931 (CII)';
  final tx = _c(root, 'SupplyChainTradeTransaction');
  final agree = _c(tx, 'ApplicableHeaderTradeAgreement');
  final settle = _c(tx, 'ApplicableHeaderTradeSettlement');
  final sum = _c(settle, 'SpecifiedTradeSettlementHeaderMonetarySummation');
  final means = _c(settle, 'SpecifiedTradeSettlementPaymentMeans');
  return EInvoice(
    format: format,
    isCreditNote: _t(root, 'ExchangedDocument/TypeCode') == '381',
    number: _t(root, 'ExchangedDocument/ID'),
    issueDate: _date(_t(root, 'ExchangedDocument/IssueDateTime/DateTimeString')),
    dueDate: _date(_t(settle, 'SpecifiedTradePaymentTerms/DueDateDateTime/DateTimeString')),
    currency: _t(settle, 'InvoiceCurrencyCode'),
    seller: _ciiParty(_c(agree, 'SellerTradeParty')),
    buyer: _ciiParty(_c(agree, 'BuyerTradeParty')),
    lines: [
      for (final l in _cs(tx, 'IncludedSupplyChainTradeLineItem'))
        InvoiceLine(
          name: _t(l, 'SpecifiedTradeProduct/Name'),
          quantity: _t(l, 'SpecifiedLineTradeDelivery/BilledQuantity'),
          unit: _p(l, 'SpecifiedLineTradeDelivery/BilledQuantity')?.getAttribute('unitCode') ?? '',
          unitPrice: _t(l, 'SpecifiedLineTradeAgreement/NetPriceProductTradePrice/ChargeAmount'),
          total: _t(l, 'SpecifiedLineTradeSettlement/SpecifiedTradeSettlementLineMonetarySummation/LineTotalAmount'),
          vatRate: _t(l, 'SpecifiedLineTradeSettlement/ApplicableTradeTax/RateApplicablePercent'),
        ),
    ],
    netTotal: _t(sum, 'TaxBasisTotalAmount'),
    taxTotal: _t(sum, 'TaxTotalAmount'),
    grandTotal: _t(sum, 'GrandTotalAmount'),
    amountDue: _t(sum, 'DuePayableAmount'),
    iban: _t(means, 'PayeePartyCreditorFinancialAccount/IBANID'),
    bic: _t(means, 'PayeeSpecifiedCreditorFinancialInstitution/BICID'),
    paymentReference: _t(settle, 'PaymentReference'),
    notes: [for (final n in _cs(_c(root, 'ExchangedDocument'), 'IncludedNote')) _t(n, 'Content')].where((s) => s.isNotEmpty).toList(),
  );
}

InvoiceParty _ublParty(XmlElement? holder) {
  final party = _c(holder, 'Party');
  final legal = _t(party, 'PartyLegalEntity/RegistrationName');
  return InvoiceParty(
    name: legal.isNotEmpty ? legal : _t(party, 'PartyName/Name'),
    vatId: _t(party, 'PartyTaxScheme/CompanyID'),
    street: _t(party, 'PostalAddress/StreetName'),
    postcode: _t(party, 'PostalAddress/PostalZone'),
    city: _t(party, 'PostalAddress/CityName'),
    country: _t(party, 'PostalAddress/Country/IdentificationCode'),
    email: _t(party, 'Contact/ElectronicMail'),
  );
}

EInvoice _ubl(XmlElement root) {
  final custom = _t(root, 'CustomizationID').toLowerCase();
  final format = custom.contains('xrechnung') ? 'XRechnung (UBL)' : (custom.contains('peppol') ? 'Peppol BIS (UBL)' : 'EN 16931 (UBL)');
  final credit = root.name.local == 'CreditNote';
  final means = _c(root, 'PaymentMeans');
  final totals = _c(root, 'LegalMonetaryTotal');
  return EInvoice(
    format: format,
    isCreditNote: credit,
    number: _t(root, 'ID'),
    issueDate: _date(_t(root, 'IssueDate')),
    dueDate: _date(_t(root, 'DueDate')),
    currency: _t(root, 'DocumentCurrencyCode'),
    seller: _ublParty(_c(root, 'AccountingSupplierParty')),
    buyer: _ublParty(_c(root, 'AccountingCustomerParty')),
    lines: [
      for (final l in _cs(root, credit ? 'CreditNoteLine' : 'InvoiceLine'))
        InvoiceLine(
          name: _t(l, 'Item/Name'),
          quantity: _t(l, credit ? 'CreditedQuantity' : 'InvoicedQuantity'),
          unit: _c(l, credit ? 'CreditedQuantity' : 'InvoicedQuantity')?.getAttribute('unitCode') ?? '',
          unitPrice: _t(l, 'Price/PriceAmount'),
          total: _t(l, 'LineExtensionAmount'),
          vatRate: _t(l, 'Item/ClassifiedTaxCategory/Percent'),
        ),
    ],
    netTotal: _t(totals, 'TaxExclusiveAmount'),
    taxTotal: _t(root, 'TaxTotal/TaxAmount'),
    grandTotal: _t(totals, 'TaxInclusiveAmount'),
    amountDue: _t(totals, 'PayableAmount'),
    iban: _t(means, 'PayeeFinancialAccount/ID'),
    bic: _t(means, 'PayeeFinancialAccount/FinancialInstitutionBranch/ID'),
    paymentReference: _t(means, 'PaymentID'),
    notes: [for (final n in _cs(root, 'Note')) n.innerText.trim()].where((s) => s.isNotEmpty).toList(),
  );
}

InvoiceParty _fatturaParty(XmlElement? p) {
  final reg = _p(p, 'DatiAnagrafici/Anagrafica');
  final person = [_t(reg, 'Nome'), _t(reg, 'Cognome')].where((s) => s.isNotEmpty).join(' ');
  final vat = _p(p, 'DatiAnagrafici/IdFiscaleIVA');
  return InvoiceParty(
    name: _t(reg, 'Denominazione').isNotEmpty ? _t(reg, 'Denominazione') : person,
    vatId: vat == null ? '' : '${_t(vat, 'IdPaese')}${_t(vat, 'IdCodice')}',
    street: _t(p, 'Sede/Indirizzo'),
    postcode: _t(p, 'Sede/CAP'),
    city: _t(p, 'Sede/Comune'),
    country: _t(p, 'Sede/Nazione'),
  );
}

EInvoice _fattura(XmlElement root) {
  final header = _c(root, 'FatturaElettronicaHeader');
  final body = _c(root, 'FatturaElettronicaBody');
  final general = _p(body, 'DatiGenerali/DatiGeneraliDocumento');
  final payment = _p(body, 'DatiPagamento/DettaglioPagamento');
  final summaries = _cs(_c(body, 'DatiBeniServizi'), 'DatiRiepilogo').toList();
  double sum(String field) => summaries.fold(0.0, (a, s) => a + (double.tryParse(_t(s, field)) ?? 0));
  final net = summaries.isEmpty ? '' : sum('ImponibileImporto').toStringAsFixed(2);
  final tax = summaries.isEmpty ? '' : sum('Imposta').toStringAsFixed(2);
  final type = _t(general, 'TipoDocumento');
  return EInvoice(
    format: 'FatturaPA',
    isCreditNote: type == 'TD04',
    number: _t(general, 'Numero'),
    issueDate: _date(_t(general, 'Data')),
    dueDate: _date(_t(payment, 'DataScadenzaPagamento')),
    currency: _t(general, 'Divisa'),
    seller: _fatturaParty(_c(header, 'CedentePrestatore')),
    buyer: _fatturaParty(_c(header, 'CessionarioCommittente')),
    lines: [
      for (final l in _cs(_c(body, 'DatiBeniServizi'), 'DettaglioLinee'))
        InvoiceLine(
          name: _t(l, 'Descrizione'),
          quantity: _t(l, 'Quantita'),
          unit: _t(l, 'UnitaMisura'),
          unitPrice: _t(l, 'PrezzoUnitario'),
          total: _t(l, 'PrezzoTotale'),
          vatRate: _t(l, 'AliquotaIVA'),
        ),
    ],
    netTotal: net,
    taxTotal: tax,
    grandTotal: _t(general, 'ImportoTotaleDocumento'),
    amountDue: _t(payment, 'ImportoPagamento'),
    iban: _t(payment, 'IBAN'),
    bic: _t(payment, 'BIC'),
    notes: [for (final n in _cs(general, 'Causale')) n.innerText.trim()].where((s) => s.isNotEmpty).toList(),
  );
}
