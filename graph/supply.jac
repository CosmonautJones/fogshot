"""Own-side power. Intact Cable edges conduct. Rubble and foreign nodes do not.

These nodes are not attached to root. The visualizer graph is not the supply graph.
"""

node Site {
    has name: str;
    has owner: str;
    has kind: str;
    has intact: bool = True;
}

edge Cable: Site --> Site {
    has intact: bool = True;
}

obj SupplyReport {
    has powered: list[str] = [];
    has targets: list[str] = [];
    has shot_ready: bool = True;
}

walker PowerWalk {
    has owner: str;
    has start_name: str;
    has started: bool = False;
    has seen: list[str] = [];
    has powered: list[str] = [];
    has reports: list[list[str]] = [];

    can walk with Site entry {
        if not self.started {
            self.started = True;
            self.seen = [];
            self.powered = [];
        }
        if here.name in self.seen {
            return;
        }
        self.seen.append(here.name);
        if here.owner != self.owner {
            return;
        }
        if here.kind == "objective" and here.intact {
            self.powered.append(here.name);
        }
        if not here.intact {
            return;
        }
        visit [->:Cable:intact == True:->];
    }

    can finish with Site exit {
        if here.name == self.start_name {
            report self.powered;
        }
    }
}

def assess(source: Site, objectives: list[Site]) -> SupplyReport {
    walked = source spawn PowerWalk(owner=source.owner, start_name=source.name);
    powered: list[str] = [];
    if walked.reports {
        powered = walked.reports[0];
    }
    targets: list[str] = [];
    for item in objectives {
        if item.owner == source.owner and item.kind == "objective" {
            targets.append(item.name);
        }
    }
    return SupplyReport(powered=powered, targets=targets, shot_ready=True);
}
