// Saving an order as database rows: nothing is ever deleted, removed parts get
// deleted_at, and Undo can bring a removed part back on the same row.
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/data/ids.dart';
import 'package:wo_tracker/data/order_rows.dart';
import 'package:wo_tracker/domain/order_input.dart';

void main() {
  const cache = OrderCache('open', 'civil', 0, 10);
  var n = 0;
  String newId() => 'new-${++n}';

  List<RowWrite> writes(OrderInput? before, OrderInput after) => orderWrites(before, after,
      contractorId: null, districtId: null, cache: cache, nowIso: '2026-10-12T06:00:00Z', newId: newId, segmentStepKeys: const {'asphalt_done'});

  const seg = Segment(id: 'seg-1', base: 'asphalt', width: 40, lengthM: 12);
  const base = OrderInput(id: 'wo-1', type: '402', category: 'extension', woNumber: '1234567', receivedDate: '2026-10-01', meters: [Meter('m-1')]);

  test('a new order inserts the order and its parts', () {
    final w = writes(null, base.copyWith(segments: [seg]));
    expect(w.first.table, 'work_orders');
    expect(w.first.kind, 'insert');
    expect(w.where((x) => x.table == 'segments').single.kind, 'upsert'); // has its own id already
    expect(w.where((x) => x.table == 'meters').single.values['seq'], 1);
  });

  test('removing a part marks it deleted, never deletes it', () {
    final before = base.copyWith(segments: [seg]);
    final w = writes(before, base);
    final s = w.where((x) => x.table == 'segments').single;
    expect(s.kind, 'update');
    expect(s.values, {'deleted_at': '2026-10-12T06:00:00Z'});
  });

  test('Undo puts a removed part back on the same row', () {
    final w = writes(base, base.copyWith(segments: [seg]));
    final s = w.where((x) => x.table == 'segments').single;
    expect(s.id, 'seg-1');
    expect(s.kind, 'upsert');
    expect(s.values['deleted_at'], isNull);
    expect(s.values.containsKey('deleted_at'), isTrue);
  });

  test('a part without an id gets a new one and is inserted', () {
    final w = writes(base, base.copyWith(cableRuns: const [CableRun(sizeMm2: 185, voltage: 'LV', lengthM: 40)]));
    final c = w.where((x) => x.table == 'cable_runs').single;
    expect(c.kind, 'insert');
    expect(c.id, startsWith('new-'));
  });

  test('a cleared step keeps its row with the date removed', () {
    final done = base.copyWith(steps: {'kashfeya': const StepRecord(done: '2026-10-02')});
    final w = writes(done, base);
    final st = w.where((x) => x.table == 'steps').single;
    expect(st.id, StepIds.stepRowId('wo-1', 'kashfeya'));
    expect(st.kind, 'upsert');
    expect(st.values['done_date'], isNull);
    expect(st.values['not_applicable'], 0);
  });

  test('an unchanged order writes nothing', () {
    expect(writes(base, base), isEmpty);
  });

  test('rows read back give the same order', () {
    final o = orderFromRows(
      const OrderRows({'id': 'wo-1', 'type_code': '402', 'category': 'extension', 'wo_number': '1234567', 'received_date': '2026-10-01', 'needs_excavation': 0, 'state': 'open'},
          segments: [
            {'id': 'seg-1', 'base': 'asphalt', 'width_cm': 40, 'length_m': '12.5', 'tiled': 0, 'created_at': '2026-10-01T08:00:00Z'},
            {'id': 'seg-2', 'base': 'soil', 'width_cm': 40, 'length_m': 3, 'tiled': 0, 'created_at': '2026-10-01T09:00:00Z', 'deleted_at': '2026-10-02T09:00:00Z'},
          ],
          steps: [
            {'id': 'x', 'step_key': 'kashfeya', 'done_date': '2026-10-02', 'not_applicable': 0},
            {'id': 'y', 'step_key': 'excavation', 'done_date': null, 'not_applicable': 0},
          ]),
    );
    expect(o.segments.map((s) => s.id), ['seg-1']); // deleted segment left out
    expect(o.segments.single.lengthM, 12.5); // numeric arrives as text from sync
    expect(o.steps.keys, ['kashfeya']); // a cleared step row is not a record
  });
}
