// Every kind of matter, in the order the Hand weighs them (counsel.js runs each): a new kind is a new class here,
// never another branch in counsel.js.
import { Cold } from "./cold.js";
import { Usurper, Rose } from "./usurper.js";
import { Ultimatum } from "./ultimatum.js";
import { Dead } from "./dead.js";
import { Attack } from "./attack.js";
import { Hunger } from "./hunger.js";
import { HostHunger } from "./host_hunger.js";
import { HouseWar } from "./house_war.js";
import { ThinTreasury, FullTreasury } from "./treasury.js";
import { Plague, Unrest, Walls } from "./town.js";
import { Loyal, Match } from "./house.js";
import { Threat } from "./threat.js";
import { Warden, Fate, Defiant } from "./warden.js";

export const KINDS = [new Warden(), new Fate(), new Defiant(), new Cold(), new Usurper(), new Rose(), new Ultimatum(), new Dead(), new Attack(), new Hunger(), new HostHunger(), new HouseWar(), new ThinTreasury(),
  new Plague(), new Unrest(), new Walls(), new Loyal(), new FullTreasury(), new Match(), new Threat()];
