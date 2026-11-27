// Plain-English names for the car and locomotive codes the railroads report, and the
// typical equipment for Amtrak services (Amtrak publishes no live equipment data).

export const CAR_MODELS: Record<string, { name: string; maker: string; kind: 'electric' | 'locomotive' | 'coach' }> = {
  // LIRR
  M7: { name: 'M7', maker: 'Bombardier', kind: 'electric' },
  M9: { name: 'M9', maker: 'Kawasaki', kind: 'electric' },
  M3: { name: 'M3', maker: 'Budd', kind: 'electric' },
  DEDM: { name: 'DE30AC / DM30AC', maker: 'EMD', kind: 'locomotive' },
  C3: { name: 'C3 bilevel', maker: 'Kawasaki', kind: 'coach' },
  // Metro-North
  M8: { name: 'M8', maker: 'Kawasaki', kind: 'electric' },
  M7A: { name: 'M7A', maker: 'Bombardier', kind: 'electric' },
  M3A: { name: 'M3A', maker: 'Budd', kind: 'electric' },
  SC: { name: 'Charger', maker: 'Siemens', kind: 'locomotive' },
  P32: { name: 'P32AC-DM', maker: 'GE', kind: 'locomotive' },
  BL20: { name: 'BL20GH', maker: 'Brookville', kind: 'locomotive' },
  SL: { name: 'Shoreliner', maker: 'Bombardier', kind: 'coach' },
};

/** "M7_LIRR" style fleet codes -> what the whole train is. */
export function fleetName(fleet: string | undefined, firstCarType?: string): string {
  if (!fleet) return 'Equipment not reported';
  if (fleet.endsWith('_DIESEL')) {
    const loco = firstCarType ? CAR_MODELS[firstCarType] : undefined;
    return loco ? `${loco.maker} ${loco.name} diesel` : 'Diesel train';
  }
  const m = CAR_MODELS[fleet];
  return m ? `${m.maker} ${m.name} electric` : fleet;
}

export interface TypicalEquipment { summary: string; detail: string; source: string }

/**
 * Typical Amtrak equipment by service (late 2026). Not live: Amtrak does not publish which
 * locomotive or set runs a given train. Sources: Amtrak press releases and fleet rosters.
 */
const AMTRAK_TYPICAL: [RegExp, TypicalEquipment][] = [
  [/^Acela/i, { summary: 'Avelia Liberty (NextGen Acela)', detail: 'Alstom high-speed trainset; a few runs may still use a first-generation Acela set', source: 'https://media.amtrak.com/2026/07/nextgen-acela-fleet-continues-to-grow/' }],
  [/Northeast Regional|Keystone|Vermonter|Valley Flyer|Hartford|Carolinian|Palmetto|Pennsylvanian|Downeaster/i,
    { summary: 'Siemens ACS-64 + Amfleet I', detail: 'Electric locomotive on the Northeast Corridor; diesel (ALC-42 or P42DC) where the wires end', source: 'https://en.wikipedia.org/wiki/List_of_Amtrak_rolling_stock' }],
  [/Empire|Adirondack|Ethan Allen|Maple Leaf|Berkshire/i,
    { summary: 'GE P32AC-DM + Amfleet', detail: 'Dual-mode locomotive, the only Amtrak engine that can run on third rail into Penn Station', source: 'https://en.wikipedia.org/wiki/GE_Genesis' }],
  [/Lake Shore|Cardinal|Crescent|Silver|Floridian|Capitol/i,
    { summary: 'Siemens ALC-42 + Viewliner / Amfleet II', detail: 'Long-distance diesel; swaps to an ACS-64 electric for the Northeast Corridor', source: 'https://en.wikipedia.org/wiki/Siemens_Charger' }],
];

export function amtrakTypical(routeName: string): TypicalEquipment | null {
  for (const [re, eq] of AMTRAK_TYPICAL) if (re.test(routeName)) return eq;
  return null;
}
