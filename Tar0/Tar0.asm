command: push segment static index 0
command: pop segment local index 4
command: gt
counter: 1
command: push segment constant index 7
command: gt
counter: 2
command: pop segment this index 2
command: push segment constant index 3
command: add
command: push segment argument index 1
command: eq
counter: 3
command: pop segment that index 2
command: push segment constant index 3
command: lt
counter: 1
command: pop segment pointer index 1
command: push segment constant index 43
command: push segment local index 4
command: neg
command: sub
command: eq
counter: 2
