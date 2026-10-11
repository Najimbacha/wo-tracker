// Plain input model for the rules engine. The database layer maps rows into
// these objects; the golden test fixtures use the same JSON shape.

class Segment {
  final String id;
  final String base; // 'soil' | 'asphalt'
  final int width; // 40 | 80
  final double lengthM;
  final bool tiled;

  const Segment({required this.id, required this.base, required this.width, required this.lengthM, this.tiled = false});

  factory Segment.fromJson(Map<String, dynamic> j) => Segment(
        id: j['id'] as String,
        base: j['base'] as String,
        width: (j['width'] as num).toInt(),
        lengthM: (j['lengthM'] as num? ?? 0).toDouble(),
        tiled: j['tiled'] as bool? ?? false,
      );
}

class Meter {
  final String id;
  final String? number;
  final String? oldNumber;
  final String? meterType; // single_phase | three_phase | ct
  final int? breakerAmps;
  const Meter(this.id, {this.number, this.oldNumber, this.meterType, this.breakerAmps});
  factory Meter.fromJson(Map<String, dynamic> j) => Meter(j['id'] as String,
      number: j['number'] as String?,
      oldNumber: j['oldNumber'] as String?,
      meterType: j['meterType'] as String?,
      breakerAmps: (j['breakerAmps'] as num?)?.toInt());
}

class CableRun {
  final int sizeMm2;
  final String voltage; // 'LV' | 'MV'
  final double lengthM;
  const CableRun({required this.sizeMm2, required this.voltage, required this.lengthM});
  factory CableRun.fromJson(Map<String, dynamic> j) =>
      CableRun(sizeMm2: (j['sizeMm2'] as num).toInt(), voltage: j['voltage'] as String, lengthM: (j['lengthM'] as num).toDouble());
}

class Permit {
  final String? number;
  final String? appliedDate;
  final String? startDate;
  final String? endDate;
  const Permit({this.number, this.appliedDate, this.startDate, this.endDate});
  factory Permit.fromJson(Map<String, dynamic> j) => Permit(
        number: j['number'] as String?,
        appliedDate: j['appliedDate'] as String?,
        startDate: j['startDate'] as String?,
        endDate: j['endDate'] as String?,
      );
}

class StepRecord {
  final String? done; // completion date
  final bool na; // not applicable
  final String? reason;
  final String? note; // free note on the step; kept when the step is marked or cleared
  const StepRecord({this.done, this.na = false, this.reason, this.note});
  bool get closed => done != null || na;
  factory StepRecord.fromJson(Map<String, dynamic> j) => StepRecord(
      done: j['done'] as String?, na: j['na'] as bool? ?? false, reason: j['reason'] as String?, note: j['note'] as String?);
  Map<String, Object?> toJson() => {
        if (na) ...{'na': true, 'reason': reason} else if (done != null) 'done': done,
        if (note != null) 'note': note,
      };
}

class HoldPeriod {
  final String from;
  final String? to;
  final String? reason;
  final String? review; // date to look at it again
  const HoldPeriod({required this.from, this.to, this.reason, this.review});
  factory HoldPeriod.fromJson(Map<String, dynamic> j) => HoldPeriod(
      from: j['from'] as String, to: j['to'] as String?, reason: j['reason'] as String?, review: j['review'] as String?);
  HoldPeriod endedOn(String date) => HoldPeriod(from: from, to: date, reason: reason, review: review);
  Map<String, Object?> toJson() => {'from': from, 'to': to, 'reason': reason, if (review != null) 'review': review};
}

// Lets copyWith tell "leave as is" apart from "set to null".
const Object _keep = Object();

class OrderInput {
  final String? id;
  final String type;
  final String category; // 'extension' | 'emergency'
  final String? woNumber;
  final String? receivedDate;
  final bool needsExcavation;
  final List<Segment> segments;
  final List<Meter> meters;
  final List<CableRun> cableRuns;
  final List<Permit> permits;
  final Map<String, StepRecord> steps;
  final String state; // 'open' | 'on_hold' | 'cancelled' | 'merged'
  final String? stateReason; // why cancelled / merged
  final String? stateDate; // the day it was cancelled / merged
  final String? mergedInto; // id of the order that replaced this one
  final List<HoldPeriod> holdPeriods;
  final String? lastChangeDate;
  final String? contractor;
  final String? district;
  final String? street;
  final String? networkRef;
  final String? notes;
  final bool deleted;

  const OrderInput({
    this.id,
    required this.type,
    required this.category,
    this.woNumber,
    this.receivedDate,
    this.needsExcavation = false,
    this.segments = const [],
    this.meters = const [],
    this.cableRuns = const [],
    this.permits = const [],
    this.steps = const {},
    this.state = 'open',
    this.stateReason,
    this.stateDate,
    this.mergedInto,
    this.holdPeriods = const [],
    this.lastChangeDate,
    this.contractor,
    this.district,
    this.street,
    this.networkRef,
    this.notes,
    this.deleted = false,
  });

  factory OrderInput.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        ((j[k] as List?) ?? const []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    final status = (j['status'] as Map?)?.cast<String, dynamic>();
    return OrderInput(
      id: j['id'] as String?,
      type: j['type'] as String,
      category: j['category'] as String,
      woNumber: j['woNumber'] as String?,
      receivedDate: j['receivedDate'] as String?,
      needsExcavation: j['needsExcavation'] as bool? ?? false,
      segments: list('segments', Segment.fromJson),
      meters: list('meters', Meter.fromJson),
      cableRuns: list('cableRuns', CableRun.fromJson),
      permits: list('permits', Permit.fromJson),
      steps: ((j['steps'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k as String, StepRecord.fromJson(Map<String, dynamic>.from(v as Map)))),
      state: status?['state'] as String? ?? 'open',
      stateReason: status?['reason'] as String?,
      stateDate: status?['date'] as String?,
      mergedInto: status?['mergedInto'] as String?,
      holdPeriods: ((status?['holdPeriods'] as List?) ?? const [])
          .map((e) => HoldPeriod.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      lastChangeDate: j['lastChangeDate'] as String?,
      contractor: j['contractor'] as String?,
      district: j['district'] as String?,
      street: j['street'] as String?,
      networkRef: j['networkRef'] as String?,
      notes: j['notes'] as String?,
      deleted: j['deleted'] as bool? ?? false,
    );
  }

  OrderInput copyWith({
    String? type,
    bool? needsExcavation,
    List<Segment>? segments,
    List<Meter>? meters,
    List<CableRun>? cableRuns,
    List<Permit>? permits,
    Map<String, StepRecord>? steps,
    String? state,
    Object? stateReason = _keep,
    Object? stateDate = _keep,
    Object? mergedInto = _keep,
    List<HoldPeriod>? holdPeriods,
    Object? lastChangeDate = _keep,
    String? woNumber,
    Object? networkRef = _keep,
    Object? street = _keep,
  }) =>
      OrderInput(
        id: id,
        type: type ?? this.type,
        category: category,
        woNumber: woNumber ?? this.woNumber,
        receivedDate: receivedDate,
        needsExcavation: needsExcavation ?? this.needsExcavation,
        segments: segments ?? this.segments,
        meters: meters ?? this.meters,
        cableRuns: cableRuns ?? this.cableRuns,
        permits: permits ?? this.permits,
        steps: steps ?? this.steps,
        state: state ?? this.state,
        stateReason: identical(stateReason, _keep) ? this.stateReason : stateReason as String?,
        stateDate: identical(stateDate, _keep) ? this.stateDate : stateDate as String?,
        mergedInto: identical(mergedInto, _keep) ? this.mergedInto : mergedInto as String?,
        holdPeriods: holdPeriods ?? this.holdPeriods,
        lastChangeDate: identical(lastChangeDate, _keep) ? this.lastChangeDate : lastChangeDate as String?,
        contractor: contractor,
        district: district,
        street: identical(street, _keep) ? this.street : street as String?,
        networkRef: identical(networkRef, _keep) ? this.networkRef : networkRef as String?,
        notes: notes,
        deleted: deleted,
      );
}
