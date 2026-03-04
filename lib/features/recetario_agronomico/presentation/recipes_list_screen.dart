import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/services/access_controller.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../data/recetario_repo.dart';
import '../domain/models.dart';

class RecipesListScreen extends StatefulWidget {
  const RecipesListScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<RecipesListScreen> createState() => _RecipesListScreenState();
}

class _RecipesListScreenState extends State<RecipesListScreen> {
  late final RecetarioRepo _repo;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _repo = RecetarioRepo(
      firestore: FirebaseFirestore.instance,
      tenantId: widget.session.tenantId,
      currentUid: widget.session.uid,
      access: widget.session.access,
    );
  }

  bool get _canEdit => widget.session.access.canEditRecetario;

  bool get _canEmit {
    final role = widget.session.access.role;
    return role == TenantRole.admin || role == TenantRole.engineer;
  }

  Future<void> _openRecipeForm({Recipe? recipe}) async {
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.recipeForm, arguments: recipe);
  }

  Future<void> _openEmit(Recipe recipe) async {
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.emitOrder, arguments: recipe);
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompactWidth(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recetario Agronomico'),
        actions: [
          if (compact)
            PopupMenuButton<String?>(
              tooltip: 'Filtrar estado',
              icon: const Icon(Icons.filter_list),
              onSelected: (value) => setState(() => _statusFilter = value),
              itemBuilder: (context) => const [
                PopupMenuItem<String?>(value: null, child: Text('Todos')),
                PopupMenuItem<String?>(value: 'draft', child: Text('Draft')),
                PopupMenuItem<String?>(
                  value: 'published',
                  child: Text('Published'),
                ),
              ],
            )
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _statusFilter,
                hint: const Text('Estado'),
                onChanged: (value) => setState(() => _statusFilter = value),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                  DropdownMenuItem<String?>(
                    value: 'draft',
                    child: Text('Draft'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'published',
                    child: Text('Published'),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openRecipeForm(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva receta'),
            )
          : null,
      body: StreamBuilder<List<Recipe>>(
        stream: _repo.watchRecipes(status: _statusFilter),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final recipes = snapshot.data!;
          if (recipes.isEmpty) {
            return const Center(child: Text('Sin recetas cargadas.'));
          }

          return ResponsivePage(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: recipes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final recipe = recipes[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                recipe.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            _StatusChip(status: recipe.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Cultivo: ${recipe.crop} - ${recipe.stage}'),
                        const SizedBox(height: 4),
                        Text('Objetivo: ${recipe.objective}'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_canEdit)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openRecipeForm(recipe: recipe),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Editar'),
                              ),
                            if (_canEmit && recipe.status == 'published')
                              FilledButton.icon(
                                onPressed: () => _openEmit(recipe),
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Emitir recetario'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final isPublished = normalized == 'published';
    return Chip(
      label: Text(isPublished ? 'Published' : 'Draft'),
      backgroundColor: isPublished
          ? Colors.green.shade100
          : Colors.orange.shade100,
    );
  }
}
