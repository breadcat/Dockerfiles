#!/usr/bin/env python3

import duolingo
lingo = duolingo.Duolingo('repuser', password='reppass')
lingo.buy_item('streak_freeze', 'nb')
