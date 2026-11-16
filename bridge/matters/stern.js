// The hard answers to a house that defies the crown (Mac 2026-11-16: "this fucker is angry with me? i should be
// teaching him a fucking lesson"): take his heir to court as a ward, strip him of a town for a loyal house, or march
// the royal host on his seat. Shared by every matter about a defiant house (cold, ultimatum, the house that rose).
export function stern(ctx, s, pid) {
  const p = s.players.find((q) => q.id === pid);
  const seat = s.seatOf(pid);
  if (!p || !seat) return [];
  const loyal = s.great.filter((q) => q.id !== pid).sort((a, b) => ctx.favourOf(b.id) - ctx.favourOf(a.id))[0];
  const town = s.cities.filter((c) => c.owner === pid && !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0))[0];
  const name = s.short(p);
  return [
    { label: `March on ${seat.title}`, action: "march", city: seat.id },
    town && loyal ? { label: `Take ${town.title} from them for ${s.short(loyal)} (${name} −30, ${s.short(loyal)} +20)`, action: "grant", city: town.id, to: loyal.id } : null,
    !s.wardTaken(pid) ? { label: `Take their heir as your ward (${name} ${s.wardHurt}; ${s.wardFor})`, action: "ward", city: seat.id } : null,
  ];
}
