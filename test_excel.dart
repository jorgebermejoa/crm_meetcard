import 'package:excel/excel.dart';

void main() {
  var excel = Excel.createExcel();
  var sheet = excel['Sheet1'];
  sheet.updateCell(CellIndex.indexByString('A1'), TextCellValue('Hello World'));
  sheet.updateCell(CellIndex.indexByString('A2'), IntCellValue(42));
  var cell1 = sheet.cell(CellIndex.indexByString('A1'));
  var cell2 = sheet.cell(CellIndex.indexByString('A2'));
  print('Cell1 value: ${cell1.value}');
  print('Cell1 type: ${cell1.value.runtimeType}');
  print('Cell1 toString: ${cell1.value.toString()}');
  
  print('Cell2 value: ${cell2.value}');
  print('Cell2 type: ${cell2.value.runtimeType}');
  print('Cell2 toString: ${cell2.value.toString()}');
}
