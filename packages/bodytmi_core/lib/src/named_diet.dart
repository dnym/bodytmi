import 'errors.dart';

/// A named diet listed for information only (D21): a description and its
/// source. It never filters foods, marks foods or days good or bad, or
/// scores adherence; a body plan may carry one as a label (D22: curated,
/// each with its source).
typedef NamedDiet = ({
  String id,
  String name,
  String description,
  String source,
});

const List<NamedDiet> namedDiets = [
  (
    id: 'mediterranean',
    name: 'Mediterranean diet',
    description:
        'A traditional eating pattern built on vegetables, legumes, fruit, '
        'whole grains, nuts, fish and olive oil, with moderate wine and '
        'little red or processed meat. It defines no energy or macro goals.',
    source:
        'Estruch R et al. Primary prevention of cardiovascular disease with '
        'a Mediterranean diet supplemented with extra-virgin olive oil or '
        'nuts (PREDIMED). N Engl J Med 2018;378:e34.',
  ),
  (
    id: 'nordic',
    name: 'Nordic dietary pattern',
    description:
        'The dietary pattern behind the Nordic Nutrition Recommendations: '
        'mostly plant-based foods (vegetables, fruit, berries, legumes, '
        'whole grains), fish, and vegetable oils, with limited red and '
        'processed meat. It defines no energy or macro goals here.',
    source:
        'Blomhoff R et al. Nordic Nutrition Recommendations 2023. Nordic '
        'Council of Ministers, 2023.',
  ),
];

NamedDiet namedDiet(String id) =>
    namedDiets.where((d) => d.id == id).firstOrNull ??
    (throw BodyTmiException('not_found', 'Named diet not found: $id.'));

Map<String, Object?> namedDietToJson(NamedDiet d) => {
  'id': d.id,
  'name': d.name,
  'description': d.description,
  'source': d.source,
  'informationOnly': true,
};
