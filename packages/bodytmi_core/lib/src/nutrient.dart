import 'errors.dart';
import 'quantity.dart';

/// One nutrient of the fixed vocabulary. [unit] is the unit totals are shown
/// in; any unit of the same dimension may be entered. [euroFir] is the
/// EuroFIR component code the Swedish Food Agency database uses, so dataset
/// values map without guessing.
final class NutrientDefinition {
  const NutrientDefinition(
    this.id,
    this.unit,
    this.euroFir,
    this.english,
    this.swedish, {
    this.primary = false,
  });
  final String id;
  final Unit unit;
  final String euroFir;
  final String english;
  final String swedish;

  /// Reported by default: energy, protein, carbohydrate, fat and fibre.
  final bool primary;

  Map<String, Object?> toJson() => {
    'id': id,
    'unit': unit.name,
    'euroFir': euroFir,
    'names': {'en': english, 'sv': swedish},
    if (primary) 'primary': true,
  };
}

/// Energy is the food-label kilocalorie value. Carbohydrate is *available*
/// carbohydrate (EuroFIR CHO), as on EU labels, so fibre is separate.
/// Vitamin A is in retinol equivalents and niacin equivalents in mg.
const nutrients = <NutrientDefinition>[
  NutrientDefinition(
    'energy',
    Unit.kcal,
    'ENERC',
    'Energy',
    'Energi',
    primary: true,
  ),
  NutrientDefinition(
    'protein',
    Unit.g,
    'PROT',
    'Protein',
    'Protein',
    primary: true,
  ),
  NutrientDefinition(
    'carbohydrate',
    Unit.g,
    'CHO',
    'Carbohydrate, available',
    'Kolhydrater, tillgängliga',
    primary: true,
  ),
  NutrientDefinition(
    'fat',
    Unit.g,
    'FAT',
    'Fat, total',
    'Fett, totalt',
    primary: true,
  ),
  NutrientDefinition('fibre', Unit.g, 'FIBT', 'Fibre', 'Fiber', primary: true),
  NutrientDefinition(
    'sugars',
    Unit.g,
    'SUGAR',
    'Sugars, total',
    'Sockerarter, totalt',
  ),
  NutrientDefinition(
    'added-sugars',
    Unit.g,
    'SUGAD',
    'Added sugars',
    'Tillsatt socker',
  ),
  NutrientDefinition(
    'free-sugars',
    Unit.g,
    'SUGFR',
    'Free sugars',
    'Fritt socker',
  ),
  NutrientDefinition(
    'monosaccharides',
    Unit.g,
    'MNSAC',
    'Monosaccharides',
    'Monosackarider',
  ),
  NutrientDefinition(
    'disaccharides',
    Unit.g,
    'DISAC',
    'Disaccharides',
    'Disackarider',
  ),
  NutrientDefinition('sucrose', Unit.g, 'SUCS', 'Sucrose', 'Sackaros'),
  NutrientDefinition(
    'wholegrain',
    Unit.g,
    'WHOLET',
    'Wholegrain, total',
    'Fullkorn totalt',
  ),
  NutrientDefinition(
    'wholegrain-pseudocereal',
    Unit.g,
    'WHOLE_x',
    'Wholegrain from pseudocereals',
    'Fullkorn från pseudocerealier',
  ),
  NutrientDefinition(
    'saturated-fat',
    Unit.g,
    'FASAT',
    'Saturated fatty acids',
    'Summa mättade fettsyror',
  ),
  NutrientDefinition(
    'monounsaturated-fat',
    Unit.g,
    'FAMS',
    'Monounsaturated fatty acids',
    'Summa enkelomättade fettsyror',
  ),
  NutrientDefinition(
    'polyunsaturated-fat',
    Unit.g,
    'FAPU',
    'Polyunsaturated fatty acids',
    'Summa fleromättade fettsyror',
  ),
  NutrientDefinition(
    'fa-c4-c10',
    Unit.g,
    'F4-10:0',
    'Fatty acids C4:0–C10:0',
    'Fettsyra 4:0-10:0',
  ),
  NutrientDefinition(
    'fa-c12-0',
    Unit.g,
    'F12:0',
    'Lauric acid C12:0',
    'Laurinsyra C12:0',
  ),
  NutrientDefinition(
    'fa-c14-0',
    Unit.g,
    'F14:0',
    'Myristic acid C14:0',
    'Myristinsyra C14:0',
  ),
  NutrientDefinition(
    'fa-c16-0',
    Unit.g,
    'F16:0',
    'Palmitic acid C16:0',
    'Palmitinsyra C16:0',
  ),
  NutrientDefinition(
    'fa-c16-1',
    Unit.g,
    'F16:1',
    'Palmitoleic acid C16:1',
    'Palmitoljesyra C16:1',
  ),
  NutrientDefinition(
    'fa-c18-0',
    Unit.g,
    'F18:0',
    'Stearic acid C18:0',
    'Stearinsyra C18:0',
  ),
  NutrientDefinition(
    'fa-c18-1',
    Unit.g,
    'F18:1',
    'Oleic acid C18:1',
    'Oljesyra C18:1',
  ),
  NutrientDefinition(
    'fa-c18-2',
    Unit.g,
    'F18:2',
    'Linoleic acid C18:2',
    'Linolsyra C18:2',
  ),
  NutrientDefinition(
    'fa-c18-3',
    Unit.g,
    'F18:3',
    'Linolenic acid C18:3',
    'Linolensyra C18:3',
  ),
  NutrientDefinition(
    'fa-c20-0',
    Unit.g,
    'F20:0',
    'Arachidic acid C20:0',
    'Arakidinsyra C20:0',
  ),
  NutrientDefinition(
    'fa-c20-4',
    Unit.g,
    'F20:4',
    'Arachidonic acid C20:4',
    'Arakidonsyra C20:4',
  ),
  NutrientDefinition('epa', Unit.g, 'F20:5', 'EPA C20:5', 'EPA (C20:5)'),
  NutrientDefinition('dpa', Unit.g, 'F22:5', 'DPA C22:5', 'DPA (C22:5)'),
  NutrientDefinition('dha', Unit.g, 'F22:6', 'DHA C22:6', 'DHA (C22:6)'),
  NutrientDefinition(
    'cholesterol',
    Unit.mg,
    'CHORL',
    'Cholesterol',
    'Kolesterol',
  ),
  NutrientDefinition('alcohol', Unit.g, 'ALC', 'Alcohol', 'Alkohol'),
  NutrientDefinition('water', Unit.g, 'WATER', 'Water', 'Vatten'),
  NutrientDefinition('ash', Unit.g, 'ASH', 'Ash', 'Aska'),
  NutrientDefinition('salt', Unit.g, 'NACL', 'Salt', 'Salt, NaCl'),
  NutrientDefinition('sodium', Unit.mg, 'NA', 'Sodium', 'Natrium, Na'),
  NutrientDefinition('potassium', Unit.mg, 'K', 'Potassium', 'Kalium, K'),
  NutrientDefinition('calcium', Unit.mg, 'CA', 'Calcium', 'Kalcium, Ca'),
  NutrientDefinition('magnesium', Unit.mg, 'MG', 'Magnesium', 'Magnesium, Mg'),
  NutrientDefinition('phosphorus', Unit.mg, 'P', 'Phosphorus', 'Fosfor, P'),
  NutrientDefinition('iron', Unit.mg, 'FE', 'Iron', 'Järn, Fe'),
  NutrientDefinition('zinc', Unit.mg, 'ZN', 'Zinc', 'Zink, Zn'),
  NutrientDefinition('iodine', Unit.mcg, 'ID', 'Iodine', 'Jod, I'),
  NutrientDefinition('selenium', Unit.mcg, 'SE', 'Selenium', 'Selen, Se'),
  NutrientDefinition(
    'vitamin-a',
    Unit.mcg,
    'VITA',
    'Vitamin A (retinol equivalents)',
    'Vitamin A',
  ),
  NutrientDefinition('retinol', Unit.mcg, 'RETOL', 'Retinol', 'Retinol'),
  NutrientDefinition(
    'beta-carotene',
    Unit.mcg,
    'CARTBTOT',
    'Beta-carotene',
    'Betakaroten/β-Karoten',
  ),
  NutrientDefinition('vitamin-d', Unit.mcg, 'VITD', 'Vitamin D', 'Vitamin D'),
  NutrientDefinition(
    'vitamin-d-incl-25oh',
    Unit.mcg,
    'VITD_x',
    'Vitamin D including 25-OH-D3',
    'Vitamin D inkl 25-OH-D3',
  ),
  NutrientDefinition('vitamin-e', Unit.mg, 'VITE', 'Vitamin E', 'Vitamin E'),
  NutrientDefinition('thiamin', Unit.mg, 'THIACLHCL', 'Thiamin', 'Tiamin'),
  NutrientDefinition('riboflavin', Unit.mg, 'RIBF', 'Riboflavin', 'Riboflavin'),
  NutrientDefinition('niacin', Unit.mg, 'NIA', 'Niacin', 'Niacin'),
  NutrientDefinition(
    'niacin-equivalents',
    Unit.mg,
    'NIAEQ',
    'Niacin equivalents',
    'Niacinekvivalenter',
  ),
  NutrientDefinition(
    'vitamin-b6',
    Unit.mg,
    'VITB6',
    'Vitamin B6',
    'Vitamin B6',
  ),
  NutrientDefinition(
    'folate',
    Unit.mcg,
    'FOL',
    'Folate, total',
    'Folat, totalt',
  ),
  NutrientDefinition(
    'vitamin-b12',
    Unit.mcg,
    'VITB12',
    'Vitamin B12',
    'Vitamin B12',
  ),
  NutrientDefinition('vitamin-c', Unit.mg, 'VITC', 'Vitamin C', 'Vitamin C'),
];

final Map<String, NutrientDefinition> nutrientsById = {
  for (final n in nutrients) n.id: n,
};

/// Position in the vocabulary, for stable report order.
final Map<String, int> nutrientOrder = {
  for (var i = 0; i < nutrients.length; i++) nutrients[i].id: i,
};

NutrientDefinition nutrient(String id) =>
    nutrientsById[id] ?? invalid('Unknown nutrient: $id.');

/// The primary nutrients reported first.
final List<String> primaryNutrients = [
  for (final n in nutrients)
    if (n.primary) n.id,
];
