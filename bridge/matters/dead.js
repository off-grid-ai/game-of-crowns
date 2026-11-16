// The dead come south: the host from the North, what it will bring, and the men to meet it.
import { Matter, MATTERS } from "./matter.js";
import { BANDS } from "../favour.js";

export class Dead extends Matter {
  static kind = "dead";
  find(ctx, s) {
    const { threat } = s;
    if (!(threat.north > 0)) return [];
    const d = threat.dead ?? {};
    const lord = s.players.find((p) => p.id === d.owner);
    const where = d.town ? `on ${d.town}${lord ? ` (${lord.house.crown ? "the crown's own" : lord.house.name})` : ""}` : "on the North";
    const when = d.in == null ? "" : d.in <= 1 ? " The next host comes next season." : ` The next host comes in ${d.in} seasons.`;
    // Once the King's own men outnumber the host, the Hand says so and advises nothing more.
    const hold = (d.next ?? 0) - threat.ours * 200 <= 0;
    const gap = (d.next ?? 0) - threat.ours * 200 - s.bannerMen;
    return [{ urgency: hold ? 40 : 75, occur: s.turn + (d.in ?? 0), hold, onlyBanners: !hold && gap <= 0, text: hold ? "The dead come south, and you would hold" : "The dead come south",
      why: `${(d.last ?? 0).toLocaleString("en-US")} of them fell ${where} last time; ${(d.next ?? 0).toLocaleString("en-US")} will come with the next.${when} Against them: your ${(threat.ours * 200).toLocaleString("en-US")} troops${s.bannerMen ? `, and about ${s.bannerMen.toLocaleString("en-US")} more if you call the banners` : " (the banners are already called this year)"}: ${hold ? "your own men would hold" : gap <= 0 ? "with the banners, you would hold" : gap <= 600 ? `you would lose by ${gap.toLocaleString("en-US")}: a levy (600) closes it` : `you would lose by ${gap.toLocaleString("en-US")}, even with a levy`}. If every northern town falls, the realm falls with it.` }];
  }
  answers(ctx, s, m) {
    if (m.hold) return [];
    return [{ label: "Call the banners", action: "banners" }, m.onlyBanners ? null : { label: "Raise the royal levy", action: "levy" }];
  }
  silence(ctx, s, m) {
    if (m.hold) return null;
    return { shift: Object.fromEntries(s.great.filter((p) => ctx.favourOf(p.id) >= BANDS.steady).map((p) => [p.id, MATTERS.silence.loyalWonder])), text: "The King said nothing while the dead came south. The loyal houses wonder whether he still rules." };
  }
}
