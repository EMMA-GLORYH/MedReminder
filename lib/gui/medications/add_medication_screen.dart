// lib/screens/medications/add_medication_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/local_cache_service.dart';
import '../../services/medication_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/snackbar/app_snackbar.dart';
import 'add_schedule_screen.dart';

class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService.instance;

  // Text controllers
  final _genericNameCtrl = TextEditingController();
  final _brandNameCtrl = TextEditingController();
  final _dosageAmountCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Image
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;

  // Selections
  String _dosageUnit = 'mg';
  String _medicationType = 'scheduled';
  String? _pillColor;
  String? _pillShape;

  bool _isSaving = false;
  bool _submitted = false;
  bool _anySaved = false;
  bool _isCheckingName = false;
  bool _isDuplicate = false;

  // Store medication name for use in catch block
  String _currentMedicationName = '';

  // Store user data
  User? _currentUser;
  String? _patientId;
  String? _patientName;
  String? _currentUserRole;

  // Generate temp ID for pending medications
  final String _tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

  final List<String> _dosageUnits = ['mg', 'mcg', 'g', 'ml', 'units', 'tablets'];
  final List<String> _pillShapes = ['round', 'oval', 'capsule', 'rectangle', 'triangle', 'other'];
  final List<Map<String, dynamic>> _pillColors = [
    {'name': 'white', 'color': Colors.white},
    {'name': 'blue', 'color': Colors.blue},
    {'name': 'red', 'color': Colors.red},
    {'name': 'yellow', 'color': Colors.yellow},
    {'name': 'green', 'color': AppColors.primary},
    {'name': 'orange', 'color': Colors.orange},
    {'name': 'pink', 'color': Colors.pink},
    {'name': 'purple', 'color': Colors.purple},
    {'name': 'brown', 'color': Colors.brown},
  ];

  bool get _hasImage => _selectedImageBytes != null && _selectedImage != null;
  bool get _showImageError => _submitted && !_hasImage;
  bool get _showColorError => _submitted && _pillColor == null;
  bool get _showShapeError => _submitted && _pillShape == null;

  @override
  void initState() {
    super.initState();
    debugPrint('=' * 60);
    debugPrint('🚀 AddMedicationScreen - INIT');
    debugPrint('=' * 60);
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    try {
      debugPrint('📋 Step 1: Initializing screen...');
      await _loadPatientContext();
      debugPrint('📋 Step 1 Complete: Screen initialized');
    } catch (e) {
      debugPrint('❌ Error initializing screen: $e');
    }
  }

  Future<void> _loadPatientContext() async {
    try {
      debugPrint('\n🔍 Step 2: Loading patient context...');

      // Get current user using the existing getter
      debugPrint('  -> Getting current user...');
      _currentUser = _authService.currentUser;

      if (_currentUser == null) {
        debugPrint('❌ No user logged in - cannot proceed');
        if (mounted) {
          AppSnackbar.error(context, 'Please log in to add medication');
        }
        return;
      }

      debugPrint('  ✅ Current user found:');
      debugPrint('     - ID: ${_currentUser!.id}');
      debugPrint('     - Email: ${_currentUser!.email}');

      // Get user role from user metadata
      _currentUserRole = _currentUser!.userMetadata?['role'] as String?;
      debugPrint('     - Role: $_currentUserRole');
      debugPrint('     - All metadata: ${_currentUser!.userMetadata}');

      // If role is null, try to get from profile
      if (_currentUserRole == null) {
        debugPrint('  -> Role not in metadata, trying getCurrentProfile()...');
        try {
          final profile = await _authService.getCurrentProfile();
          _currentUserRole = profile?.role;
          debugPrint('     - Profile role: $_currentUserRole');
        } catch (e) {
          debugPrint('  ⚠️ Could not get profile: $e');
        }
      }

      // If the user is a caretaker, we need to get the selected patient
      if (_currentUserRole == 'caretaker') {
        debugPrint('\n  👤 User is a CARETAKER');
        debugPrint('  -> Looking for selected patient...');

        // Get selected patient from arguments
        final args = ModalRoute.of(context)?.settings.arguments;
        debugPrint('  -> Route arguments: $args');

        if (args is Map<String, dynamic>) {
          _patientId = args['patientId'] as String?;
          _patientName = args['patientName'] as String?;
          debugPrint('  ✅ Extracted from arguments:');
          debugPrint('     - Patient ID: $_patientId');
          debugPrint('     - Patient Name: $_patientName');
        }

        // If we still don't have a patient ID
        if (_patientId == null) {
          debugPrint('  ⚠️ No patient in arguments');
          debugPrint('  💡 Need to pass patientId as route arguments');

          if (mounted) {
            AppSnackbar.error(context, 'Please select a patient first from the patient list');
          }
          return;
        }

        debugPrint('  ✅ Caretaker setup complete');
      } else if (_currentUserRole == 'patient' || _currentUserRole == null) {
        // Patient is adding for themselves (or role unknown, default to patient)
        _patientId = _currentUser!.id;
        _patientName = _currentUser!.userMetadata?['full_name'] as String?;
        debugPrint('  ✅ Patient adding for themselves:');
        debugPrint('     - Patient ID: $_patientId');
        debugPrint('     - Patient Name: $_patientName');
      } else {
        debugPrint('  ⚠️ Unknown user role: $_currentUserRole');
        if (mounted) {
          AppSnackbar.error(context, 'Unknown user role. Please contact support.');
        }
        return;
      }

      debugPrint('\n✅ Step 2 Complete: Patient context loaded successfully');
      debugPrint('   Final values:');
      debugPrint('   - Current User ID: ${_currentUser!.id}');
      debugPrint('   - Current User Role: $_currentUserRole');
      debugPrint('   - Patient ID: $_patientId');
      debugPrint('   - Patient Name: $_patientName');

    } catch (e, stack) {
      debugPrint('❌ Step 2 Failed: Error loading patient context: $e');
      debugPrint('   Stack trace: $stack');
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 AddMedicationScreen - DISPOSE');
    _genericNameCtrl.dispose();
    _brandNameCtrl.dispose();
    _dosageAmountCtrl.dispose();
    _quantityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _resetForm() {
    debugPrint('🔄 Resetting form');
    _formKey.currentState?.reset();
    _genericNameCtrl.clear();
    _brandNameCtrl.clear();
    _dosageAmountCtrl.clear();
    _quantityCtrl.clear();
    _notesCtrl.clear();

    setState(() {
      _dosageUnit = 'mg';
      _medicationType = 'scheduled';
      _pillColor = null;
      _pillShape = null;
      _selectedImage = null;
      _selectedImageBytes = null;
      _isSaving = false;
      _submitted = false;
      _isCheckingName = false;
      _isDuplicate = false;
      _currentMedicationName = '';
    });
    debugPrint('✅ Form reset complete');
  }

  /// Check if medication name already exists using direct database query
  Future<Map<String, dynamic>> _checkDuplicateInDatabase(String name) async {
    debugPrint('\n🔍 Step 4: Checking for duplicate medication...');
    try {
      debugPrint('  -> Checking name: "$name"');
      final existingMedication = await MedicationService.instance.getMedicationByName(
        name.trim(),
      );

      if (existingMedication != null) {
        debugPrint('  ⚠️ DUPLICATE FOUND: "$name" already exists');
        debugPrint('  -> Existing medication ID: ${existingMedication.id}');
        return {
          'isDuplicate': true,
          'existingMedication': existingMedication,
        };
      }

      debugPrint('  ✅ No duplicate found for: "$name"');
      return {
        'isDuplicate': false,
        'existingMedication': null,
      };
    } catch (e) {
      debugPrint('  ❌ Error checking duplicate: $e');
      return {
        'isDuplicate': false,
        'error': e.toString(),
      };
    }
  }

  Future<void> _pickMedicationImage() async {
    debugPrint('\n📸 Step: Picking medication image...');
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1400,
        maxHeight: 1400,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null) {
        debugPrint('  ⚠️ User cancelled image picker');
        return;
      }

      debugPrint('  ✅ Image selected: ${image.name}');
      final bytes = await image.readAsBytes();
      debugPrint('  ✅ Image bytes loaded: ${bytes.length} bytes');

      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
      });

      debugPrint('  ✅ Image state updated');
      AppSnackbar.success(context, '✅ Medicine photo captured successfully');
    } catch (e) {
      debugPrint('  ❌ Camera error: $e');
      if (!mounted) return;
      AppSnackbar.error(context, '📷 Camera access issue. Please make sure camera permissions are enabled.');
    }
  }

  /// Save medication FIRST, then navigate to schedule
  Future<void> _saveMedication() async {
    debugPrint('\n' + '=' * 60);
    debugPrint('🎯 STEP 3: STARTING MEDICATION SAVE PROCESS');
    debugPrint('=' * 60);

    setState(() {
      _submitted = true;
      _isSaving = true;
      _isCheckingName = true;
      _isDuplicate = false;
    });

    // STEP 3.1: Validate form
    debugPrint('\n📋 Step 3.1: Validating form...');
    final formValid = _formKey.currentState?.validate() ?? false;
    debugPrint('  -> Form valid: $formValid');

    if (!formValid) {
      debugPrint('❌ Form validation failed - stopping save');
      setState(() {
        _isSaving = false;
        _isCheckingName = false;
      });
      return;
    }

    // STEP 3.2: Check image
    debugPrint('\n📋 Step 3.2: Checking image...');
    debugPrint('  -> Has image: $_hasImage');

    if (!_hasImage) {
      debugPrint('❌ No image selected - stopping save');
      AppSnackbar.error(context, '📸 Please take a photo of the medication first');
      setState(() {
        _isSaving = false;
        _isCheckingName = false;
      });
      return;
    }

    // STEP 3.3: Check pill color
    debugPrint('\n📋 Step 3.3: Checking pill color...');
    debugPrint('  -> Pill color: $_pillColor');

    if (_pillColor == null) {
      debugPrint('❌ No pill color selected - stopping save');
      AppSnackbar.error(context, '🎨 Please select the pill color to help identify it later');
      setState(() {
        _isSaving = false;
        _isCheckingName = false;
      });
      return;
    }

    // STEP 3.4: Check pill shape
    debugPrint('\n📋 Step 3.4: Checking pill shape...');
    debugPrint('  -> Pill shape: $_pillShape');

    if (_pillShape == null) {
      debugPrint('❌ No pill shape selected - stopping save');
      AppSnackbar.error(context, '🔵 Please select the pill shape for easy identification');
      setState(() {
        _isSaving = false;
        _isCheckingName = false;
      });
      return;
    }

    // STEP 3.5: Parse dosage
    debugPrint('\n📋 Step 3.5: Parsing dosage...');
    final dosageText = _dosageAmountCtrl.text.trim();
    final dosageAmount = double.tryParse(dosageText);
    debugPrint('  -> Dosage text: "$dosageText"');
    debugPrint('  -> Parsed amount: $dosageAmount');

    if (dosageAmount == null || dosageAmount <= 0) {
      debugPrint('❌ Invalid dosage amount - stopping save');
      AppSnackbar.error(context, '💊 Please enter how much of this medication to take (e.g., 500)');
      setState(() {
        _isSaving = false;
        _isCheckingName = false;
      });
      return;
    }

    // STEP 3.6: Parse quantity
    debugPrint('\n📋 Step 3.6: Parsing quantity...');
    int? quantity;
    if (_quantityCtrl.text.trim().isNotEmpty) {
      quantity = int.tryParse(_quantityCtrl.text.trim());
      debugPrint('  -> Quantity text: "${_quantityCtrl.text.trim()}"');
      debugPrint('  -> Parsed quantity: $quantity');

      if (quantity == null || quantity < 0) {
        debugPrint('❌ Invalid quantity - stopping save');
        AppSnackbar.error(context, '📦 Please enter a valid number of pills/units you have');
        setState(() {
          _isSaving = false;
          _isCheckingName = false;
        });
        return;
      }
    } else {
      debugPrint('  -> Quantity not provided (optional)');
    }

    // STEP 3.7: Check patient ID
    debugPrint('\n📋 Step 3.7: Checking patient ID...');
    debugPrint('  -> Patient ID: $_patientId');
    debugPrint('  -> Current User ID: ${_currentUser?.id}');
    debugPrint('  -> Current User Role: $_currentUserRole');

    if (_patientId == null || _patientId!.isEmpty) {
      debugPrint('❌ CRITICAL: No patient ID available');
      AppSnackbar.error(context, 'Unable to determine which patient this medication is for. Please try again.');
      setState(() {
        _isSaving = false;
        _isCheckingName = false;
      });
      return;
    }

    // STEP 3.8: Collect all form data
    final medicationName = _genericNameCtrl.text.trim();
    _currentMedicationName = medicationName;

    debugPrint('\n📋 Step 3.8: Collected all form data:');
    debugPrint('   ==================================');
    debugPrint('   Medication Name: "$medicationName"');
    debugPrint('   Patient ID: "$_patientId"');
    debugPrint('   Patient Name: "$_patientName"');
    debugPrint('   Dosage: $dosageAmount $_dosageUnit');
    debugPrint('   Type: $_medicationType');
    debugPrint('   Quantity: $quantity');
    debugPrint('   Color: $_pillColor');
    debugPrint('   Shape: $_pillShape');
    debugPrint('   Brand: ${_brandNameCtrl.text.trim().isEmpty ? "Not provided" : _brandNameCtrl.text.trim()}');
    debugPrint('   Notes: ${_notesCtrl.text.trim().isEmpty ? "Not provided" : _notesCtrl.text.trim()}');
    debugPrint('   ==================================');

    try {
      // STEP 3.9: Check for duplicate
      debugPrint('\n📋 Step 3.9: Checking for duplicate medication...');
      AppSnackbar.info(context, '🔍 Checking if "$medicationName" is already in your list...');

      final result = await _checkDuplicateInDatabase(medicationName);
      debugPrint('  -> Duplicate check result: $result');

      // Handle errors from the check
      if (result.containsKey('error')) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _isCheckingName = false;
        });
        debugPrint('  ❌ Duplicate check error: ${result['error']}');
        AppSnackbar.error(
          context,
          '😕 We had trouble checking if "$medicationName" already exists. Please try again.',
        );
        return;
      }

      final isDuplicate = result['isDuplicate'] as bool;

      if (isDuplicate) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _isCheckingName = false;
          _isDuplicate = true;
        });

        debugPrint('  ⚠️ DUPLICATE DETECTED - stopping save');
        AppSnackbar.error(
          context,
          '"$medicationName" is already in your medication list.',
        );
        return;
      }

      // STEP 3.10: Proceed to upload image
      debugPrint('\n📋 Step 3.10: Starting image upload...');
      setState(() {
        _isCheckingName = false;
      });

      AppSnackbar.info(context, '📤 Saving "$medicationName" and its photo...');

      String imageUrl;
      try {
        debugPrint('  -> Uploading image: ${_selectedImage!.name}');
        debugPrint('  -> Image bytes size: ${_selectedImageBytes!.length} bytes');

        imageUrl = await MedicationService.instance.uploadMedicationImage(
          bytes: _selectedImageBytes!,
          fileName: _selectedImage!.name,
        );

        debugPrint('  ✅ Image uploaded successfully');
        debugPrint('  -> Image URL: $imageUrl');
      } catch (e) {
        debugPrint('  ❌ Image upload failed: $e');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
        });
        AppSnackbar.error(
          context,
          '📸 Could not upload the photo for "$medicationName". Please check your connection and try again.',
        );
        return;
      }

      // STEP 3.11: Save medication to database
      debugPrint('\n📋 Step 3.11: Saving medication to database...');
      debugPrint('  -> Calling MedicationService.instance.addMedication()');

      final medication = await MedicationService.instance.addMedication(
        genericName: medicationName,
        brandName: _brandNameCtrl.text.trim().isEmpty ? null : _brandNameCtrl.text.trim(),
        dosageAmount: dosageAmount,
        dosageUnit: _dosageUnit,
        medicationType: _medicationType,
        currentQuantity: quantity,
        pillColor: _pillColor!,
        pillShape: _pillShape!,
        pillImageUrl: imageUrl,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        patientId: _patientId!,
      );

      debugPrint('  ✅ Medication saved successfully!');
      debugPrint('  -> Medication ID: ${medication.id}');

      // STEP 3.12: Cache locally
      debugPrint('\n📋 Step 3.12: Caching medication locally...');
      await LocalCacheService.instance.cacheMedication(medication);
      debugPrint('  ✅ Medication cached locally');

      _anySaved = true;

      if (!mounted) return;

      // STEP 3.13: Navigate based on medication type
      if (_medicationType == 'scheduled') {
        debugPrint('\n📋 Step 3.13: Medication is SCHEDULED - navigating to schedule screen');
        AppSnackbar.success(
          context,
          '✅ "$medicationName" has been saved! Let\'s set up when to take it.',
        );

        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddScheduleScreen(
              medicationId: medication.id,
              medicationName: medication.genericName,
              onOptimisticDoses: (doses) {
                debugPrint('  📊 ${doses.length} doses scheduled for $medicationName');
              },
              onSaveCompleted: () {
                debugPrint('  ✅ Schedule saved for $medicationName');
              },
              onSaveFailed: (error) {
                debugPrint('  ❌ Failed to save schedule for $medicationName: $error');
              },
            ),
          ),
        );

        if (mounted) {
          Navigator.pop(context, result == true || _anySaved);
        }
      } else {
        debugPrint('\n📋 Step 3.13: Medication is AS NEEDED - no schedule needed');
        AppSnackbar.success(
          context,
          '✅ "$medicationName" has been saved and is ready when you need it!',
        );
        if (mounted) {
          Navigator.pop(context, true);
        }
      }

      debugPrint('\n✅ STEP 3 COMPLETE: Medication saved successfully!');

    } catch (e, stack) {
      debugPrint('\n❌ STEP 3 FAILED: Error saving medication');
      debugPrint('   Error: $e');
      debugPrint('   Stack trace: $stack');
      debugPrint('\n💡 Debugging Information:');
      debugPrint('   ================================');
      debugPrint('   Current User ID: ${_currentUser?.id}');
      debugPrint('   Current User Role: $_currentUserRole');
      debugPrint('   Patient ID: $_patientId');
      debugPrint('   Patient Name: $_patientName');
      debugPrint('   Medication Name: $_currentMedicationName');
      debugPrint('   ================================');

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isCheckingName = false;
        });

        // More detailed error handling
        final errorString = e.toString().toLowerCase();
        final name = _currentMedicationName.isNotEmpty ? _currentMedicationName : 'this medication';

        if (errorString.contains('duplicate') ||
            errorString.contains('already exists') ||
            errorString.contains('unique constraint') ||
            errorString.contains('unique_violation') ||
            errorString.contains('23505')) {

          debugPrint('  ⚠️ Database constraint violation detected');
          AppSnackbar.error(
            context,
            '"$name" already exists in your list.',
          );
        } else if (errorString.contains('network') ||
            errorString.contains('timeout') ||
            errorString.contains('connection') ||
            errorString.contains('socket')) {

          debugPrint('  ⚠️ Network error detected');
          AppSnackbar.error(
            context,
            '📡 Network issue while saving "$name". Please check your internet connection and try again.',
          );
        } else if (errorString.contains('foreign key') ||
            errorString.contains('patient_id') ||
            errorString.contains('patient') ||
            errorString.contains('user_id')) {

          debugPrint('  ⚠️ Patient relationship error');
          AppSnackbar.error(
            context,
            '👤 There was an issue linking this medication to the patient. Please try again.',
          );
        } else {
          debugPrint('  ⚠️ Unknown error type - showing generic message');
          // Show a truncated error for debugging
          final truncatedError = e.toString().length > 100
              ? e.toString().substring(0, 100)
              : e.toString();
          AppSnackbar.error(
            context,
            '😕 We couldn\'t save "$name" right now. Error: $truncatedError',
          );
        }
      }
    }

    debugPrint('\n' + '=' * 60);
    debugPrint('🏁 MEDICATION SAVE PROCESS COMPLETED');
    debugPrint('=' * 60 + '\n');
  }

  Future<bool> _onWillPop() async {
    Navigator.pop(context, _anySaved);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Medication'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context, _anySaved),
          ),
        ),
        body: SafeArea(
          child: _patientId == null && _currentUserRole == 'caretaker'
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(
                    'No Patient Selected',
                    style: AppTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please go back and select a patient\nbefore adding medication.',
                    style: AppTextStyles.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Go Back',
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
          )
              : Column(
            children: [
              // Fixed top image card
              Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AddImageCard(
                      imageBytes: _selectedImageBytes,
                      onTap: _pickMedicationImage,
                      onRemove: _selectedImageBytes == null
                          ? null
                          : () {
                        setState(() {
                          _selectedImage = null;
                          _selectedImageBytes = null;
                        });
                      },
                    ),
                    if (_showImageError) ...[
                      const SizedBox(height: 8),
                      Text(
                        '📸 Please add a medicine image to continue',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Scrollable form content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          icon: Icons.medication_rounded,
                          title: 'Medication Details',
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _genericNameCtrl,
                          label: 'Medication Name',
                          hint: 'e.g. Acetaminophen',
                          prefixIcon: Icons.medication_outlined,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter the medication name';
                            }
                            if (v.trim().length < 2) {
                              return 'Name seems too short. Please enter the full name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _brandNameCtrl,
                          label: 'Brand Name (optional)',
                          hint: 'e.g. Tylenol',
                          prefixIcon: Icons.label_outline,
                          validator: (v) {
                            if (v != null && v.trim().isNotEmpty && v.trim().length < 2) {
                              return 'Brand name seems too short';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: AppTextField(
                                controller: _dosageAmountCtrl,
                                label: 'Dosage',
                                hint: '500',
                                prefixIcon: Icons.scale_outlined,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Please enter the dosage amount';
                                  final amount = double.tryParse(v.trim());
                                  if (amount == null || amount <= 0) return 'Please enter a valid number';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DropdownField(
                                label: 'Unit',
                                value: _dosageUnit,
                                items: _dosageUnits,
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _dosageUnit = v);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _SectionHeader(
                          icon: Icons.category_rounded,
                          title: 'Medication Type',
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: _TypeCard(
                                label: 'Scheduled',
                                icon: Icons.schedule_rounded,
                                description: 'Take at fixed times each day',
                                selected: _medicationType == 'scheduled',
                                onTap: () => setState(() => _medicationType = 'scheduled'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TypeCard(
                                label: 'As Needed',
                                icon: Icons.medical_services_rounded,
                                description: 'Take only when needed',
                                selected: _medicationType == 'prn',
                                onTap: () => setState(() => _medicationType = 'prn'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _SectionHeader(
                          icon: Icons.palette_rounded,
                          title: 'Pill Identification',
                          subtitle: 'This helps us identify your medication later',
                        ),
                        const SizedBox(height: 12),

                        Text('What color is your pill?', style: AppTextStyles.labelLarge),
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _pillColors.map((c) {
                            final selected = _pillColor == c['name'];
                            return _ColorChip(
                              color: c['color'] as Color,
                              name: c['name'] as String,
                              selected: selected,
                              onTap: () {
                                setState(() => _pillColor = c['name'] as String);
                              },
                            );
                          }).toList(),
                        ),

                        if (_showColorError)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '🎨 Please select the pill color',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),

                        Text('What shape is your pill?', style: AppTextStyles.labelLarge),
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _pillShapes.map((s) {
                            final selected = _pillShape == s;
                            return _ShapeChip(
                              label: s,
                              selected: selected,
                              onTap: () => setState(() => _pillShape = s),
                            );
                          }).toList(),
                        ),

                        if (_showShapeError)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '🔵 Please select the pill shape',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),

                        _SectionHeader(
                          icon: Icons.inventory_2_rounded,
                          title: 'Your Supply',
                          subtitle: 'Optional - helps you know when to refill',
                        ),
                        const SizedBox(height: 12),

                        AppTextField(
                          controller: _quantityCtrl,
                          label: 'How many do you have?',
                          hint: 'e.g. 30 pills',
                          prefixIcon: Icons.medication_liquid_outlined,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final qty = int.tryParse(v.trim());
                            if (qty == null || qty < 0) return 'Please enter a valid number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _notesCtrl,
                          label: 'Notes (optional)',
                          hint: 'e.g. Take with food in the morning',
                          prefixIcon: Icons.note_alt_outlined,
                          maxLines: 3,
                          validator: (v) {
                            if (v != null && v.trim().length > 300) {
                              return 'Notes can be up to 300 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),

              // Fixed bottom save button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: AppButton(
                    label: _isCheckingName
                        ? 'Checking if medication exists...'
                        : 'Save Medication',
                    icon: Icons.check_rounded,
                    isLoading: _isSaving || _isCheckingName,
                    onPressed: _saveMedication,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════
// FORM DATA - Captures all form values for background save
// ══════════════════════════════════════════════════════════════
class _MedicationFormData {
  final String genericName;
  final String? brandName;
  final double dosageAmount;
  final String dosageUnit;
  final String medicationType;
  final int? currentQuantity;
  final String pillColor;
  final String pillShape;
  final String? notes;
  final Uint8List imageBytes;
  final String imageName;

  const _MedicationFormData({
    required this.genericName,
    this.brandName,
    required this.dosageAmount,
    required this.dosageUnit,
    required this.medicationType,
    this.currentQuantity,
    required this.pillColor,
    required this.pillShape,
    this.notes,
    required this.imageBytes,
    required this.imageName,
  });
}

// ══════════════════════════════════════════════════════════════
// ADD IMAGE CARD
// ══════════════════════════════════════════════════════════════
class _AddImageCard extends StatelessWidget {
  final Uint8List? imageBytes;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _AddImageCard({
    required this.imageBytes,
    required this.onTap,
    this.onRemove,
  });

  bool get hasImage => imageBytes != null;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 120,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: hasImage
                  ? null
                  : LinearGradient(
                colors: [
                  AppColors.secondary,
                  AppColors.secondaryLight,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              color: hasImage ? AppColors.surface : null,
              borderRadius: BorderRadius.circular(20),
              border: hasImage ? Border.all(color: AppColors.border) : null,
              image: hasImage
                  ? DecorationImage(
                image: MemoryImage(imageBytes!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.35),
                  BlendMode.darken,
                ),
              )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasImage
                        ? Colors.white.withValues(alpha: 0.9)
                        : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasImage
                        ? Icons.camera_alt_rounded
                        : Icons.add_a_photo_rounded,
                    color: AppColors.secondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasImage ? 'Medicine photo taken' : 'Take a photo',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasImage
                            ? 'Tap to retake if needed'
                            : 'Show us what the pill looks like',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
        if (hasImage && onRemove != null)
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECTION HEADER
// ══════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.secondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.titleMedium),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: AppTextStyles.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DROPDOWN FIELD
// ══════════════════════════════════════════════════════════════
class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down_rounded),
              style: AppTextStyles.bodyLarge,
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e),
                ),
              )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TYPE CARD
// ══════════════════════════════════════════════════════════════
class _TypeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.label,
    required this.icon,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? AppColors.secondary : AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.titleSmall.copyWith(
                color: selected ? AppColors.secondary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: AppTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// COLOR CHIP
// ══════════════════════════════════════════════════════════════
class _ColorChip extends StatelessWidget {
  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  bool get _isLight =>
      color == Colors.white ||
          color == Colors.yellow ||
          color == const Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.secondary : AppColors.border,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
            Icons.check_rounded,
            size: 20,
            color: _isLight ? AppColors.secondary : Colors.white,
          )
              : null,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SHAPE CHIP
// ══════════════════════════════════════════════════════════════
class _ShapeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? AppColors.secondary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}