// The realm's calendar, the one owner of "a year is four seasons" (integration audit #3): a turn is a season,
// spring first. Everything that counts in years, or acts once a year, asks here.
export const SEASONS = ["spring", "summer", "autumn", "winter"];
export const SEASONS_PER_YEAR = SEASONS.length;
const CONQUEST_YEAR = 300;  // the realm's calendar starts 300 years after the Conquest

// A turn's season and year ("Autumn of 312 AC").
export function calendar(turn) {
  const t = Math.max(1, Number(turn) || 1) - 1;
  const season = SEASONS[t % SEASONS_PER_YEAR];
  const year = CONQUEST_YEAR + Math.floor(t / SEASONS_PER_YEAR);
  return { season, year, text: `${season[0].toUpperCase()}${season.slice(1)} of ${year} AC` };
}

// The last season of a year (winter): what is done once a year is done then.
export const isYearEnd = (turn) => Number(turn) % SEASONS_PER_YEAR === 0;
// The first season of a year (spring).
export const isYearStart = (turn) => (Number(turn) - 1) % SEASONS_PER_YEAR === 0;
// Seasons in a number of years, and whole years in a number of seasons.
export const seasonsIn = (years) => Number(years) * SEASONS_PER_YEAR;
export const yearsIn = (seasons) => Number(seasons) / SEASONS_PER_YEAR;
