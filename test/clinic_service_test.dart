import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_bcksnap/services/api_client.dart';
import 'package:flutter_bcksnap/services/clinic_service.dart';

void main() {
  test('clinic service accepts a healthy backend response', () async {
    final service = ClinicService(
      api: ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient(
          (_) async =>
              http.Response('{"status":"ok","database":"connected"}', 200),
        ),
      ),
    );

    await expectLater(service.checkHealth(), completes);
  });

  test('clinic service distinguishes a failed database health check', () async {
    final service = ClinicService(
      api: ApiClient(
        baseUrl: 'http://localhost:8000',
        httpClient: MockClient(
          (_) async =>
              http.Response('{"status":"ok","database":"disconnected"}', 200),
        ),
      ),
    );

    await expectLater(
      service.checkHealth(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('database health check did not pass'),
        ),
      ),
    );
  });

  group('Appointment status labels', () {
    test('all persisted appointment states have readable labels', () {
      expect(appointmentStatusLabel('pending'), 'Pending');
      expect(appointmentStatusLabel('approved'), 'Approved');
      expect(appointmentStatusLabel('rejected'), 'Rejected');
      expect(appointmentStatusLabel('declined'), 'Rejected');
      expect(appointmentStatusLabel('cancelled'), 'Cancelled');
      expect(appointmentStatusLabel('completed'), 'Completed');
    });
  });

  group('Appointment availability display', () {
    test(
      'only an active appointment at least 24 hours away can be cancelled',
      () {
        final base = DateTime.now().toUtc().add(const Duration(days: 2));
        final appointment = ClinicAppointment(
          id: 1,
          userId: 2,
          status: 'approved',
          mode: 'physical',
          scheduledAt: base,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          clinicId: 3,
          clinicName: 'Clinic',
          clinicAddress: 'Address',
          doctorId: 4,
          doctorName: 'Doctor',
          reference: 'BS-TEST',
          cancellationReason: null,
        );
        expect(appointment.canCancel, isTrue);
        expect(
          _copy(
            appointment,
            scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 23)),
          ).canCancel,
          isFalse,
        );
        expect(_copy(appointment, status: 'cancelled').canCancel, isFalse);
        expect(_copy(appointment, status: 'completed').canCancel, isFalse);
      },
    );
  });

  test(
    'clinic coordinates and doctor specializations are parsed from API data',
    () {
      final clinic = ClinicInfo.fromJson({
        'id': 1,
        'name': 'Verified clinic',
        'address': '10 Test Street',
        'latitude': 14.5,
        'longitude': 120.9,
        'timezone': 'Asia/Manila',
        'supports_online': true,
        'supports_physical': false,
        'services': [
          {'id': 1, 'name': 'Spine care', 'specialization': 'Orthopedics'},
        ],
        'doctors': [
          {
            'id': 2,
            'user_id': 3,
            'name': 'Dr Test',
            'specializations': ['Orthopedics'],
            'supports_online': true,
            'supports_physical': false,
          },
        ],
      });
      expect(clinic.hasMapLocation, isTrue);
      expect(clinic.services, ['Spine care']);
      expect(clinic.doctors.single.specializations, ['Orthopedics']);
      expect(clinic.supportsOnline, isTrue);
      expect(clinic.supportsPhysical, isFalse);
    },
  );

  test('demo booking data is parsed and remains explicitly marked', () {
    final clinic = ClinicInfo.fromJson({
      'id': 7,
      'name': 'Demo clinic',
      'address': 'Development address',
      'supports_online': false,
      'supports_physical': false,
      'demo_operating_hours': {
        'monday': [
          {'open': '09:00', 'close': '12:00'},
          {'open': '13:00', 'close': '17:00'},
        ],
      },
      'demo_appointment_types': [
        {
          'mode': 'online',
          'name': 'Online appointment — SIMULATED DEMO ONLY',
          'simulation_only': true,
        },
      ],
      'doctors': [
        {
          'id': 8,
          'user_id': 9,
          'name': 'DEMO — Fictional Provider',
          'specializations': ['DEMO — Orthopedics'],
          'is_demo': true,
        },
      ],
    });

    expect(clinic.supportsOnline, isFalse);
    expect(clinic.demoAppointmentTypes.single.simulationOnly, isTrue);
    expect(clinic.demoOperatingHours['monday'], hasLength(2));
    expect(clinic.doctors.single.isDemo, isTrue);
  });

  test(
    'coordinates outside valid latitude and longitude ranges are not mapped',
    () {
      final clinic = ClinicInfo.fromJson({
        'id': 2,
        'name': 'Invalid coordinates',
        'address': 'Address',
        'latitude': 95,
        'longitude': 200,
        'timezone': 'UTC',
        'supports_online': false,
        'supports_physical': true,
      });
      expect(clinic.hasMapLocation, isFalse);
    },
  );
}

ClinicAppointment _copy(
  ClinicAppointment source, {
  DateTime? scheduledAt,
  String? status,
}) => ClinicAppointment(
  id: source.id,
  userId: source.userId,
  status: status ?? source.status,
  mode: source.mode,
  scheduledAt: scheduledAt ?? source.scheduledAt,
  createdAt: source.createdAt,
  updatedAt: source.updatedAt,
  clinicId: source.clinicId,
  clinicName: source.clinicName,
  clinicAddress: source.clinicAddress,
  doctorId: source.doctorId,
  doctorName: source.doctorName,
  reference: source.reference,
  cancellationReason: source.cancellationReason,
);
