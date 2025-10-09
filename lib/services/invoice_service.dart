import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:number_to_words_english/number_to_words_english.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class InvoiceService {
  final SupabaseClient supabase;
  InvoiceService(this.supabase);

  Future<String?> generateInvoiceForOrder(String orderId) async {
    try {
      print('=== INVOICE GENERATION START ===');
      print('Order ID: $orderId');

      final order = await _fetchOrder(orderId);
      if (order == null) {
        print('ERROR: Order not found');
        throw Exception('Order not found for ID: $orderId');
      }

      final items = await _fetchOrderItems(orderId);
      if (items.isEmpty) {
        print('ERROR: No items found');
        throw Exception('No items found for order: $orderId');
      }

      final calc = _computeBill(order, items);
      final pdfBytes = await _generatePDF(order, items, calc);

      final path = 'invoices/$orderId/${calc.invoiceNo}.pdf';
      final url = await _uploadToStorage(
        bucket: 'invoices',
        path: path,
        bytes: pdfBytes,
      );

      if (url == null) {
        throw Exception('Failed to upload invoice');
      }

      await _insertInvoiceRow(orderId, calc.invoiceNo, url, calc);

      print('=== INVOICE GENERATION SUCCESS ===');
      return url;
    } catch (e, stackTrace) {
      print('=== INVOICE GENERATION FAILED ===');
      print('ERROR: $e');
      print('STACK TRACE:');
      print(stackTrace);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchOrder(String orderId) async {
    try {
      final res = await supabase
          .from('orders')
          .select('''
            *,
            address_details,
            order_billing_details(*)
          ''')
          .eq('id', orderId)
          .maybeSingle();

      if (res == null) return null;

      final order = Map<String, dynamic>.from(res);

      if (order['order_billing_details'] != null &&
          order['order_billing_details'] is! List) {
        order['order_billing_details'] = [order['order_billing_details']];
      }

      return order;
    } catch (e) {
      print('Error in _fetchOrder: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOrderItems(String orderId) async {
    try {
      final res = await supabase
          .from('order_items')
          .select()
          .eq('order_id', orderId);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      print('Error in _fetchOrderItems: $e');
      rethrow;
    }
  }

  Future<String?> _uploadToStorage({
    required String bucket,
    required String path,
    required List<int> bytes,
  }) async {
    try {
      await supabase.storage.from(bucket).uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'application/pdf',
        ),
      );
      final url = supabase.storage.from(bucket).getPublicUrl(path);
      return url;
    } catch (e) {
      print('Error in _uploadToStorage: $e');
      return null;
    }
  }

  _ComputedBill _computeBill(
      Map<String, dynamic> order,
      List<Map<String, dynamic>> items,
      ) {
    try {
      final billing = (() {
        final l = order['order_billing_details'];
        if (l is List && l.isNotEmpty) {
          return Map<String, dynamic>.from(l.first);
        }
        return <String, dynamic>{};
      })();

      final subtotal = _num(billing['subtotal']);
      final discount = _num(billing['discount_amount']);
      final minimumCartFee = _num(billing['minimum_cart_fee']);
      final platformFee = _num(billing['platform_fee']);
      final serviceTax = _num(billing['service_tax']);
      final deliveryFee = _num(billing['delivery_fee']);
      final totalAmount = _num(billing['total_amount']);

      final discountedSubtotal = max(0, subtotal - discount);

      final cgstTotal = serviceTax / 2;
      final sgstTotal = serviceTax / 2;

      num totalQty = 0;
      for (final it in items) {
        totalQty += _num(it['quantity']);
      }

      final perItem = <_ItemComputed>[];
      for (final it in items) {
        final itemTotal = _num(it['total_price']);
        final qty = _num(it['quantity']);
        final unitPrice = _num(it['product_price']);

        final weight = subtotal > 0 ? itemTotal / subtotal : 0;
        final itemDiscount = discount * weight;
        final itemSubtotalAfterDiscount = max(0, itemTotal - itemDiscount);

        final itemTaxable = itemSubtotalAfterDiscount / 1.18;
        final itemCGST = itemTaxable * 0.09;
        final itemSGST = itemTaxable * 0.09;
        final itemTotalWithGST = itemTaxable + itemCGST + itemSGST;

        perItem.add(_ItemComputed(
          name: _s(it['product_name']),
          qty: qty,
          unitPrice: unitPrice,
          uqc: 'NOS',
          hsn: '9997',
          discount: itemDiscount,
          taxable: itemTaxable,
          cgstPct: 9,
          sgstPct: 9,
          cgst: itemCGST,
          sgst: itemSGST,
          total: itemTotalWithGST,
        ));
      }

      final feeRows = <_FeeRow>[];

      if (platformFee > 0) {
        final taxable = platformFee / 1.18;
        final cg = taxable * 0.09;
        final sg = taxable * 0.09;
        feeRows.add(_FeeRow(
          'Platform Fee',
          '9997',
          1,
          taxable,
          0,
          taxable,
          9,
          9,
          cg,
          sg,
          platformFee,
        ));
      }

      if (minimumCartFee > 0) {
        final taxable = minimumCartFee / 1.18;
        final cg = taxable * 0.09;
        final sg = taxable * 0.09;
        feeRows.add(_FeeRow(
          'Minimum Cart Fee',
          '9997',
          1,
          taxable,
          0,
          taxable,
          9,
          9,
          cg,
          sg,
          minimumCartFee,
        ));
      }

      if (deliveryFee > 0) {
        final taxable = deliveryFee / 1.18;
        final cg = taxable * 0.09;
        final sg = taxable * 0.09;
        feeRows.add(_FeeRow(
          'Delivery Fee',
          '996813',
          1,
          taxable,
          0,
          taxable,
          9,
          9,
          cg,
          sg,
          deliveryFee,
        ));
      }

      final now = DateTime.now();
      final rnd = Random().nextInt(9000) + 1000;
      final invoiceNo = 'INV-${DateFormat('yyMMdd').format(now)}-$rnd';

      final amountInWords = NumberToWordsEnglish.convert(totalAmount.round());
      final capitalizedWords = amountInWords.isEmpty
          ? 'Zero only'
          : '${amountInWords[0].toUpperCase()}${amountInWords.substring(1)} only';

      num totalTaxable = 0;
      for (final item in perItem) {
        totalTaxable += item.taxable;
      }
      for (final fee in feeRows) {
        totalTaxable += fee.taxable;
      }

      return _ComputedBill(
        invoiceNo: invoiceNo,
        subtotal: subtotal,
        totalQty: totalQty,
        discount: discount,
        taxableTotal: totalTaxable,
        cgstTotal: cgstTotal,
        sgstTotal: sgstTotal,
        grandTotal: totalAmount,
        amountInWords: capitalizedWords,
        coupon: _s(order['applied_coupon_code']),
        customer: _readCustomer(order),
        paymentMethod: _s(order['payment_method']).toUpperCase(),
        items: perItem,
        feeRows: feeRows,
      );
    } catch (e) {
      print('Error in _computeBill: $e');
      rethrow;
    }
  }

  Future<List<int>> _generatePDF(
      Map<String, dynamic> order,
      List<Map<String, dynamic>> items,
      _ComputedBill calc,
      ) async {
    try {
      final doc = PdfDocument();
      final page = doc.pages.add();
      final g = page.graphics;
      final size = page.getClientSize();

      final black = PdfColor(0, 0, 0);
      final borderColor = PdfColor(200, 200, 200);
      final headerBg = PdfColor(240, 240, 240);
      final pen = PdfPen(borderColor, width: 0.5);

      final fTitle = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
      final fBold11 = PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
      final fBold10 = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
      final fBold9 = PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);
      final fBold8 = PdfStandardFont(PdfFontFamily.helvetica, 8, style: PdfFontStyle.bold);
      final fReg9 = PdfStandardFont(PdfFontFamily.helvetica, 9);
      final fReg8 = PdfStandardFont(PdfFontFamily.helvetica, 8);
      final fReg7 = PdfStandardFont(PdfFontFamily.helvetica, 7);
      final fReg6 = PdfStandardFont(PdfFontFamily.helvetica, 6);

      double y = 20;
      final leftMargin = 20.0;
      final rightMargin = size.width - 20;
      final contentWidth = rightMargin - leftMargin;

      // ========== LOGO AND TAX INVOICE HEADER ==========
      g.drawString('Dobify', fTitle, bounds: Rect.fromLTWH(leftMargin, y, 100, 18));
      g.drawString('Tax Invoice', fTitle,
          bounds: Rect.fromLTWH(rightMargin - 120, y, 120, 18),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));

      y += 30;

      // ========== INVOICE FROM BOX ==========
      final fromBoxHeight = 105.0;
      g.drawRectangle(pen: pen, bounds: Rect.fromLTWH(leftMargin, y, contentWidth, fromBoxHeight));

      double innerY = y + 8;
      g.drawString('Invoice From', fBold10, bounds: Rect.fromLTWH(leftMargin + 5, innerY, 200, 10));

      innerY += 15;
      g.drawString('LEOWORKS PRIVATE LIMITED', fBold11, bounds: Rect.fromLTWH(leftMargin + 5, innerY, 300, 10));

      innerY += 13;
      g.drawString('Ground Floor, Plot No-362, Damana Road, Chandrasekharpur', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 5, innerY, 350, 10));

      innerY += 11;
      g.drawString('Bhubaneswar-751024, Khordha, Odisha', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 5, innerY, 300, 10));

      innerY += 11;
      g.drawString('Email ID: info@dobify.in', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 5, innerY, 200, 10));

      innerY += 11;
      g.drawString('PIN Code: 751016', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 5, innerY, 200, 10));

      double rightX = rightMargin - 210;
      double rightY = y + 28;

      g.drawString('GSTIN: 21AAGCL4609M1ZH', fReg8, bounds: Rect.fromLTWH(rightX, rightY, 210, 10));
      rightY += 11;
      g.drawString('CIN: U62011OD2025PTC050462', fReg8, bounds: Rect.fromLTWH(rightX, rightY, 210, 10));
      rightY += 11;
      g.drawString('PAN: AAGCL4609M', fReg8, bounds: Rect.fromLTWH(rightX, rightY, 210, 10));
      rightY += 11;
      g.drawString('TAN: BBNL01690D', fReg8, bounds: Rect.fromLTWH(rightX, rightY, 210, 10));

      y += fromBoxHeight + 5;

      // ========== ORDER DETAILS BOX ==========
      final orderBoxHeight = 65.0;
      g.drawRectangle(pen: pen, bounds: Rect.fromLTWH(leftMargin, y, contentWidth, orderBoxHeight));

      final centerX = leftMargin + (contentWidth / 2);
      g.drawLine(pen, Offset(centerX, y), Offset(centerX, y + orderBoxHeight));

      innerY = y + 8;
      _drawLabelValue(g, fReg8, fReg8, 'Order Id:', _s(order['id']), leftMargin + 5, innerY, 50);
      innerY += 14;
      _drawLabelValue(g, fReg8, fReg8, 'Invoice No:', calc.invoiceNo, leftMargin + 5, innerY, 60);

      innerY = y + 8;
      _drawLabelValue(g, fReg8, fReg8, 'Invoice Date:', _fmtDate(order['created_at']),
          centerX + 5, innerY, 70);
      innerY += 14;
      _drawLabelValue(g, fReg8, fReg8, 'Place of Supply:', 'Odisha', centerX + 5, innerY, 90);
      innerY += 14;
      _drawLabelValue(g, fReg8, fReg8, 'State Code:', '21', centerX + 5, innerY, 70);

      y += orderBoxHeight + 5;

      // ========== INVOICE TO BOX ==========
      final invoiceToHeight = 50.0;
      g.drawRectangle(pen: pen, bounds: Rect.fromLTWH(leftMargin, y, contentWidth, invoiceToHeight));

      innerY = y + 8;
      g.drawString('Invoice To', fBold10, bounds: Rect.fromLTWH(leftMargin + 5, innerY, 200, 10));

      innerY += 14;
      g.drawString(calc.customer.name, fReg9, bounds: Rect.fromLTWH(leftMargin + 5, innerY, 500, 10));

      innerY += 12;
      g.drawString(calc.customer.line1, fReg8, bounds: Rect.fromLTWH(leftMargin + 5, innerY, 500, 10));

      innerY += 10;
      g.drawString(calc.customer.line2, fReg8, bounds: Rect.fromLTWH(leftMargin + 5, innerY, 500, 10));

      y += invoiceToHeight + 5;

      // ========== CATEGORY BAR ==========
      final categoryHeight = 18.0;
      g.drawRectangle(pen: pen, bounds: Rect.fromLTWH(leftMargin, y, contentWidth, categoryHeight));

      g.drawString('Category: B2C', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 5, y + 5, 150, 10));
      g.drawString('Reverse Charges Applicable: No', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 150, y + 5, 200, 10));
      g.drawString('Transaction Type: ${calc.paymentMethod}', fReg8,
          bounds: Rect.fromLTWH(rightMargin - 180, y + 5, 180, 10));

      y += categoryHeight + 5;

      // ========== ITEMS TABLE ==========
      final tableWidth = contentWidth;
      final rowH = 20.0; // Increased for better readability

      final colWidths = [30.0, 120.0, 50.0, 50.0, 30.0, 35.0, 50.0, 60.0, 40.0, 50.0, 40.0, 50.0, 60.0];
      final colX = <double>[leftMargin];
      for (int i = 0; i < colWidths.length - 1; i++) {
        colX.add(colX[i] + colWidths[i]);
      }

      // Table header
      g.drawRectangle(brush: PdfSolidBrush(headerBg), pen: pen,
          bounds: Rect.fromLTWH(leftMargin, y, tableWidth, rowH));

      final headers = [
        'Sr.\nNo.',
        'Item Description',
        'HSN/\nSAC',
        'Unit\nPrice',
        'Qty.',
        'UQC',
        'Discount',
        'Taxable\nAmount',
        'CGST\n(%)',
        'CGST\n(INR)',
        'SGST\n(%)',
        'SGST\n(INR)',
        'Total\n(INR)'
      ];

      for (int i = 0; i < headers.length; i++) {
        g.drawString(headers[i], fBold8,
            bounds: Rect.fromLTWH(colX[i] + 2, y + 3, colWidths[i] - 4, rowH - 6),
            format: PdfStringFormat(alignment: PdfTextAlignment.center, lineAlignment: PdfVerticalAlignment.middle));
      }

      for (int i = 0; i <= colWidths.length; i++) {
        final x = (i == 0) ? leftMargin : colX[i - 1] + colWidths[i - 1];
        g.drawLine(pen, Offset(x, y), Offset(x, y + rowH));
      }

      y += rowH;

      // ========== ITEMS DATA ROWS ==========
      int sr = 1;
      for (final item in calc.items) {
        _drawTableRow(g, pen, fReg7, leftMargin, colX, colWidths, rowH, y, [
          sr.toString(),
          _truncate(item.name, 30),
          item.hsn,
          _moneyPlain(item.unitPrice),
          _qty(item.qty),
          item.uqc,
          _moneyPlain(item.discount),
          _moneyPlain(item.taxable),
          '${item.cgstPct.toInt()}',
          _moneyPlain(item.cgst),
          '${item.sgstPct.toInt()}',
          _moneyPlain(item.sgst),
          _moneyPlain(item.total),
        ]);
        y += rowH;
        sr++;
      }

      // Fee rows
      for (final fee in calc.feeRows) {
        _drawTableRow(g, pen, fReg7, leftMargin, colX, colWidths, rowH, y, [
          sr.toString(),
          fee.title,
          fee.hsn,
          _moneyPlain(fee.unit),
          _qty(fee.qty),
          'OTH',
          _moneyPlain(fee.discount),
          _moneyPlain(fee.taxable),
          '${fee.cgstPct.toInt()}',
          _moneyPlain(fee.cgst),
          '${fee.sgstPct.toInt()}',
          _moneyPlain(fee.sgst),
          _moneyPlain(fee.total),
        ]);
        y += rowH;
        sr++;
      }

      // ========== TOTALS ROW ==========
      g.drawRectangle(brush: PdfSolidBrush(headerBg), pen: pen,
          bounds: Rect.fromLTWH(leftMargin, y, tableWidth, rowH));

      g.drawString('Total', fBold9, bounds: Rect.fromLTWH(colX[0] + 2, y + 6, 100, 10));
      g.drawString(_qty(calc.totalQty), fBold9,
          bounds: Rect.fromLTWH(colX[4] + 2, y + 6, colWidths[4] - 4, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.center));
      g.drawString(_moneyPlain(calc.discount), fBold9,
          bounds: Rect.fromLTWH(colX[6] + 2, y + 6, colWidths[6] - 4, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));
      g.drawString(_moneyPlain(calc.taxableTotal), fBold9,
          bounds: Rect.fromLTWH(colX[7] + 2, y + 6, colWidths[7] - 4, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));
      g.drawString(_moneyPlain(calc.cgstTotal), fBold9,
          bounds: Rect.fromLTWH(colX[9] + 2, y + 6, colWidths[9] - 4, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));
      g.drawString(_moneyPlain(calc.sgstTotal), fBold9,
          bounds: Rect.fromLTWH(colX[11] + 2, y + 6, colWidths[11] - 4, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));
      g.drawString(_moneyPlain(calc.grandTotal), fBold9,
          bounds: Rect.fromLTWH(colX[12] + 2, y + 6, colWidths[12] - 4, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));

      for (int i = 0; i <= colWidths.length; i++) {
        final x = (i == 0) ? leftMargin : colX[i - 1] + colWidths[i - 1];
        g.drawLine(pen, Offset(x, y), Offset(x, y + rowH));
      }

      y += rowH + 10;

      // ========== COUPON & AMOUNT IN WORDS ==========
      final couponText = calc.coupon.isEmpty ? '-' : calc.coupon;
      g.drawString('Coupon Applied: $couponText', fReg9,
          bounds: Rect.fromLTWH(leftMargin + 5, y, 400, 10));

      y += 18;
      g.drawString('Amount in Words:', fBold9,
          bounds: Rect.fromLTWH(leftMargin + 5, y, 120, 10));
      g.drawString(calc.amountInWords, fReg9,
          bounds: Rect.fromLTWH(leftMargin + 125, y, 400, 10));

      y += 30;

      // ========== SIGNATURE SECTION ==========
      g.drawString('For Dobify', fBold10,
          bounds: Rect.fromLTWH(rightMargin - 150, y, 150, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));

      y += 8;
      g.drawString('A trade of Leoworks Private Limited', fReg8,
          bounds: Rect.fromLTWH(rightMargin - 180, y, 180, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));

      y += 20;
      g.drawString('Digitally Signed by', fReg8,
          bounds: Rect.fromLTWH(rightMargin - 150, y, 150, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));

      y += 10;
      g.drawString('Leoworks Private Limited.', fReg8,
          bounds: Rect.fromLTWH(rightMargin - 150, y, 150, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));

      y += 10;
      g.drawString(_fmtDate(order['created_at']), fReg8,
          bounds: Rect.fromLTWH(rightMargin - 150, y, 150, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));

      y += 20;

      // ========== COMPANY DETAILS BOX ==========
      final detailsBoxHeight = 30.0;
      g.drawRectangle(pen: pen, bounds: Rect.fromLTWH(leftMargin, y, contentWidth, detailsBoxHeight));

      innerY = y + 7;
      g.drawString('GSTIN: 21AAGCL4609M1ZH', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 5, innerY, 220, 10));
      g.drawString('PAN: AAGCL4609M', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 230, innerY, 150, 10));

      innerY += 12;
      g.drawString('CIN: U62011OD2025PTC050462', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 5, innerY, 250, 10));
      g.drawString('TAN: BBNL01690D', fReg8,
          bounds: Rect.fromLTWH(leftMargin + 230, innerY, 150, 10));

      y += detailsBoxHeight + 15;

      // ========== FOOTER INFO ==========
      g.drawString(
          'Registered Office: Ground Floor, Plot No-362, Damana Road, Chandrasekharpur, Bhubaneswar-751024, Khordha, Odisha',
          fReg7, bounds: Rect.fromLTWH(leftMargin + 5, y, contentWidth - 10, 15));

      y += 13;
      g.drawString('Email: info@dobify.in | Contact: +91 7326019870 | Website: www.dobify.in',
          fReg7, bounds: Rect.fromLTWH(leftMargin + 5, y, contentWidth - 10, 10));

      y += 18;
      g.drawString('Note:', fBold9, bounds: Rect.fromLTWH(leftMargin + 5, y, 50, 10));

      y += 11;
      g.drawString(
          'This is a digitally signed computer-generated invoice and does not require a signature. All transactions are subject to the terms and conditions of Dobify.',
          fReg7, bounds: Rect.fromLTWH(leftMargin + 5, y, contentWidth - 10, 20));

      y += 20;
      g.drawString('Terms & Conditions:', fBold9, bounds: Rect.fromLTWH(leftMargin + 5, y, 150, 10));

      y += 12;
      final terms = [
        '1. If you have any issues or queries regarding your order, please contact our customer chat support through the Dobify platform or email us at info@dobify.in',
        '2. For your safety, please note that Dobify never asks for sensitive banking details such as CVV, account number, UPI PIN, or passwords through any support channel. Do not share these details with anyone over any medium.',
        '3. All services are provided by Dobify, a trade of Leoworks Private Limited.',
        '4. Refunds or cancellations, if applicable, will be processed as per Dobify\'s refund and cancellation policy.',
        '5. Dobify shall not be held responsible for delays or issues arising from factors beyond its control.',
        '6. Any disputes shall be subject to the jurisdiction of Bhubaneswar, Odisha.',
      ];

      for (final term in terms) {
        g.drawString(term, fReg7, bounds: Rect.fromLTWH(leftMargin + 5, y, contentWidth - 10, 18));
        y += 12;
      }

      final bytes = await doc.save();
      doc.dispose();
      return bytes;
    } catch (e, stackTrace) {
      print('Error in _generatePDF: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  void _drawTableRow(
      PdfGraphics g,
      PdfPen pen,
      PdfFont font,
      double leftMargin,
      List<double> colX,
      List<double> colWidths,
      double rowHeight,
      double y,
      List<String> values,
      ) {
    final tableWidth = colX.last + colWidths.last - leftMargin;
    g.drawRectangle(pen: pen, bounds: Rect.fromLTWH(leftMargin, y, tableWidth, rowHeight));

    for (int i = 0; i <= colWidths.length; i++) {
      final x = (i == 0) ? leftMargin : colX[i - 1] + colWidths[i - 1];
      g.drawLine(pen, Offset(x, y), Offset(x, y + rowHeight));
    }

    for (int i = 0; i < values.length && i < colX.length; i++) {
      final alignment = (i == 0 || i == 1 || i == 2 || i == 5)
          ? PdfTextAlignment.left
          : PdfTextAlignment.right;

      g.drawString(values[i], font,
          bounds: Rect.fromLTWH(colX[i] + 2, y + 6, colWidths[i] - 4, rowHeight - 12),
          format: PdfStringFormat(alignment: alignment, lineAlignment: PdfVerticalAlignment.middle));
    }
  }

  void _drawLabelValue(
      PdfGraphics g,
      PdfFont labelFont,
      PdfFont valueFont,
      String label,
      String value,
      double x,
      double y,
      double labelWidth,
      ) {
    g.drawString(label, labelFont, bounds: Rect.fromLTWH(x, y, labelWidth, 10));
    g.drawString(value, valueFont, bounds: Rect.fromLTWH(x + labelWidth, y, 300, 10));
  }

  Future<void> _insertInvoiceRow(
      String orderId,
      String invoiceNo,
      String? url,
      _ComputedBill c,
      ) async {
    try {
      await supabase.from('invoices').insert({
        'order_id': orderId,
        'invoice_no': invoiceNo,
        'invoice_url': url,
        'invoice_date': DateTime.now().toIso8601String(),
        'total_amount': c.grandTotal,
        'taxable_total': c.taxableTotal,
        'discount_total': c.discount,
        'cgst_total': c.cgstTotal,
        'sgst_total': c.sgstTotal,
        'total_qty': c.totalQty,
        'amount_in_words': c.amountInWords,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error in _insertInvoiceRow: $e');
      rethrow;
    }
  }

  String _s(dynamic v) => (v == null || v.toString() == 'null') ? '' : v.toString();

  num _num(dynamic v) => (v is num) ? v : (num.tryParse(_s(v)) ?? 0);

  String _qty(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  String _money(num v) => '₹${v.toStringAsFixed(2)}';

  String _moneyPlain(num v) => v.toStringAsFixed(2);

  String _fmtDate(dynamic iso) {
    try {
      return DateFormat('dd MMM, yyyy').format(DateTime.parse(iso.toString()));
    } catch (_) {
      return '';
    }
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  _Customer _readCustomer(Map<String, dynamic> order) {
    final m = (order['address_info'] ?? order['address_details']) ?? {};
    final name = _s(m['recipient_name']);
    final line1 = _s(m['address_line_1']);
    final parts = [
      _s(m['address_line_2']),
      _s(m['city']),
      _s(m['state']),
      _s(m['pincode']),
    ].where((e) => e.trim().isNotEmpty);
    final line2 = parts.join(', ');

    return _Customer(name: name, line1: line1, line2: line2);
  }
}

class _Customer {
  final String name;
  final String line1;
  final String line2;
  const _Customer({required this.name, required this.line1, required this.line2});
}

class _ItemComputed {
  final String name;
  final String hsn;
  final num unitPrice;
  final num qty;
  final String uqc;
  final num discount;
  final num taxable;
  final num cgstPct;
  final num cgst;
  final num sgstPct;
  final num sgst;
  final num total;

  _ItemComputed({
    required this.name,
    required this.hsn,
    required this.unitPrice,
    required this.qty,
    required this.uqc,
    required this.discount,
    required this.taxable,
    required this.cgstPct,
    required this.cgst,
    required this.sgstPct,
    required this.sgst,
    required this.total,
  });
}

class _FeeRow {
  final String title;
  final String hsn;
  final num qty;
  final num unit;
  final num discount;
  final num taxable;
  final num cgstPct;
  final num sgstPct;
  final num cgst;
  final num sgst;
  final num total;

  _FeeRow(
      this.title,
      this.hsn,
      this.qty,
      this.unit,
      this.discount,
      this.taxable,
      this.cgstPct,
      this.sgstPct,
      this.cgst,
      this.sgst,
      this.total,
      );
}

class _ComputedBill {
  final String invoiceNo;
  final num subtotal;
  final num totalQty;
  final num discount;
  final num taxableTotal;
  final num cgstTotal;
  final num sgstTotal;
  final num grandTotal;
  final String amountInWords;
  final String coupon;
  final _Customer customer;
  final String paymentMethod;
  final List<_ItemComputed> items;
  final List<_FeeRow> feeRows;

  _ComputedBill({
    required this.invoiceNo,
    required this.subtotal,
    required this.totalQty,
    required this.discount,
    required this.taxableTotal,
    required this.cgstTotal,
    required this.sgstTotal,
    required this.grandTotal,
    required this.amountInWords,
    required this.coupon,
    required this.customer,
    required this.paymentMethod,
    required this.items,
    required this.feeRows,
  });
}