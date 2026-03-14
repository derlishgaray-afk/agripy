import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/super_admin_repo.dart';

class SuperAdminSettingsScreen extends StatefulWidget {
  const SuperAdminSettingsScreen({super.key, required this.adminUid});

  final String adminUid;

  @override
  State<SuperAdminSettingsScreen> createState() =>
      _SuperAdminSettingsScreenState();
}

class _SuperAdminSettingsScreenState extends State<SuperAdminSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _whatsappController = TextEditingController();
  late final SuperAdminRepo _repo;

  bool _isLoading = true;
  bool _isSaving = false;
  String _savedWhatsapp = '';
  String _supportName = 'Administrador del sistema';

  @override
  void initState() {
    super.initState();
    _repo = SuperAdminRepo(FirebaseFirestore.instance);
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final profile = await _repo.getSuperAdminProfile(widget.adminUid);
      final systemContact = await _repo.getSystemSupportContact();
      final whatsapp =
          systemContact?.whatsapp ?? (profile?.whatsappContact ?? '');
      final profileName = (profile?.name ?? '').trim();
      final profileEmail = (profile?.email ?? '').trim();
      final resolvedSupportName = (systemContact?.name ?? '').trim().isNotEmpty
          ? systemContact!.name.trim()
          : profileName.isNotEmpty
          ? profileName
          : (profileEmail.isNotEmpty
                ? profileEmail
                : 'Administrador del sistema');
      if (!mounted) {
        return;
      }
      setState(() {
        _supportName = resolvedSupportName;
        _savedWhatsapp = whatsapp;
        _whatsappController.text = whatsapp;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar configuracion: $error')),
      );
    }
  }

  String? _normalizeWhatsapp(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) {
      return null;
    }
    return '+$digits';
  }

  Future<void> _saveWhatsapp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final normalized = _normalizeWhatsapp(_whatsappController.text);
    if (normalized == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _repo.updateSuperAdminWhatsappContact(
        uid: widget.adminUid,
        whatsappContact: normalized,
      );
      await _repo.updateSystemSupportContact(
        updatedByUid: widget.adminUid,
        supportName: _supportName,
        whatsappContact: normalized,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedWhatsapp = normalized;
        _whatsappController.text = normalized;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacto de WhatsApp guardado.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _clearWhatsapp() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _repo.updateSuperAdminWhatsappContact(
        uid: widget.adminUid,
        whatsappContact: '',
      );
      await _repo.updateSystemSupportContact(
        updatedByUid: widget.adminUid,
        supportName: _supportName,
        whatsappContact: '',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedWhatsapp = '';
        _whatsappController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacto de WhatsApp eliminado.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracion')),
      body: ResponsivePage(
        maxWidth: 680,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Text(
                    'Contacto de WhatsApp del administrador',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Este numero se usa como canal principal de contacto.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _whatsappController,
                              enabled: !_isSaving,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+\-\s\(\)]'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'WhatsApp',
                                hintText: '+595981123456',
                                helperText:
                                    'Formato internacional recomendado.',
                              ),
                              validator: (value) {
                                final input = value?.trim() ?? '';
                                if (input.isEmpty) {
                                  return 'Ingrese un numero de WhatsApp.';
                                }
                                if (_normalizeWhatsapp(input) == null) {
                                  return 'Numero invalido. Use entre 8 y 15 digitos.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            if (_savedWhatsapp.isNotEmpty)
                              Text(
                                'Guardado actualmente: $_savedWhatsapp',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: _isSaving ? null : _saveWhatsapp,
                                  icon: _isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: const Text('Guardar'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _isSaving || _savedWhatsapp.isEmpty
                                      ? null
                                      : _clearWhatsapp,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Catalogos de Productos'),
                      subtitle: const Text(
                        'Administrar productos base para registro',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.superAdminProductCatalog),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
