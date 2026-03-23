import std.stdio;
import std.string;
import std.path;
import std.file;
import std.array;
import std.conv; // להמרות מספרים למחרוזות

// משתנים גלובאליים
string currentFileName;
File outFile;
int logicCounter = 0; // מונה לייצור תוויות קפיצה ייחודיות

void main() {
    write("Please enter the directory path: ");
    string dirPath = readln().strip();

    if (!exists(dirPath) || !isDir(dirPath)) {
        writeln("Error: Directory not found.");
        return;
    }

    string dirName = baseName(dirPath);
    string outFilePath = buildPath(dirPath, dirName ~ ".asm");
    
    outFile = File(outFilePath, "w");

    foreach (string entry; dirEntries(dirPath, "*.vm", SpanMode.shallow)) {
        currentFileName = baseName(entry, ".vm");
        File inFile = File(entry, "r");

        foreach (line; inFile.byLine()) {
            string cleanLine = line.idup;
            
            // חיתוך הערות מתוך השורה (אם יש)
            auto commentPos = cleanLine.indexOf("//");
            if (commentPos != -1) {
                cleanLine = cleanLine[0 .. commentPos];
            }
            
            auto words = cleanLine.split(); 
            if (words.length == 0) continue; // דילוג על שורות ריקות

            string command = words[0];

            // כתיבת הערה בקובץ ה-asm כדי שיהיה קל לקרוא ולדבג אותו
            outFile.writeln("// " ~ cleanLine.strip());

            switch(command) {
                // אריתמטיקה ולוגיקה 
                case "add": handleArithmetic("M=D+M"); break;
                case "sub": handleArithmetic("M=M-D"); break;
                case "and": handleArithmetic("M=D&M"); break;
                case "or":  handleArithmetic("M=D|M"); break;
                case "neg": handleUnary("M=-M"); break;
                case "not": handleUnary("M=!M"); break;
                case "eq":  handleCompare("JEQ"); break;
                case "gt":  handleCompare("JGT"); break;
                case "lt":  handleCompare("JLT"); break;
                
                // גישה לזיכרון
                case "push": 
                    if (words.length >= 3) handlePush(words[1], words[2]); 
                    break;
                case "pop": 
                    if (words.length >= 3) handlePop(words[1], words[2]); 
                    break;
                default: break;
            }
        }
        inFile.close();
        writeln("End of input file: ", baseName(entry));
    }

    outFile.close();
    writeln("Output file is ready: ", dirName, ".asm");
}

// ==========================================
// פונקציות עזר לכתיבת פקודות Assembly
// ==========================================

// --- אריתמטיקה ולוגיקה ---

void handleArithmetic(string op) {
    outFile.writeln("@SP");
    outFile.writeln("AM=M-1"); // y
    outFile.writeln("D=M");
    outFile.writeln("A=A-1");  // x
    outFile.writeln(op);       // ביצוע הפעולה
}

void handleUnary(string op) {
    outFile.writeln("@SP");
    outFile.writeln("A=M-1"); // ניגש לאיבר העליון בלי לשנות את SP
    outFile.writeln(op);      // ביצוע הפעולה
}

void handleCompare(string jumpType) {
    string labelTrue = "IF_TRUE_" ~ to!string(logicCounter);
    string labelEnd = "IF_END_" ~ to!string(logicCounter);
    logicCounter++;

    outFile.writeln("@SP");
    outFile.writeln("AM=M-1");
    outFile.writeln("D=M");     // y
    outFile.writeln("A=A-1");
    outFile.writeln("D=M-D");   // x - y

    outFile.writeln("@" ~ labelTrue);
    outFile.writeln("D;" ~ jumpType); // קפיצה אם התנאי מתקיים

    outFile.writeln("@SP");     // מקרה False
    outFile.writeln("A=M-1");
    outFile.writeln("M=0");     // 0 זה שקר
    outFile.writeln("@" ~ labelEnd);
    outFile.writeln("0;JMP");

    outFile.writeln("(" ~ labelTrue ~ ")");
    outFile.writeln("@SP");     // מקרה True
    outFile.writeln("A=M-1");
    outFile.writeln("M=-1");    // 1- זה אמת

    outFile.writeln("(" ~ labelEnd ~ ")");
}

// --- גישה לזיכרון (Push / Pop) ---

void handlePush(string segment, string index) {
    if (segment == "constant") {
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
    } 
    else if (segment == "local" || segment == "argument" || segment == "this" || segment == "that") {
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
        outFile.writeln("@" ~ getSegmentSymbol(segment));
        outFile.writeln("D=D+M"); // התיקון הקריטי: מחשבים את הכתובת לתוך D במקום ל-A
        outFile.writeln("A=D");   // מעבירים את הכתובת הבטוחה ל-A
        outFile.writeln("D=M");   // קוראים את הערך המבוקש
    } 
    else if (segment == "temp") {
        int addr = 5 + to!int(index);
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("D=M");
    } 
    else if (segment == "pointer") {
        int addr = 3 + to!int(index); // 3 זה THIS, 4 זה THAT
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("D=M");
    } 
    else if (segment == "static") {
        outFile.writeln("@" ~ currentFileName ~ "." ~ index);
        outFile.writeln("D=M");
    }

    // דחיפת הערך שנמצא ב-D לתוך המחסנית וקידום SP
    outFile.writeln("@SP");
    outFile.writeln("A=M");
    outFile.writeln("M=D");
    outFile.writeln("@SP");
    outFile.writeln("M=M+1");
}

void handlePop(string segment, string index) {
    if (segment == "local" || segment == "argument" || segment == "this" || segment == "that") {
        // חישוב כתובת היעד ושמירתה ברגיסטר זמני R13
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
        outFile.writeln("@" ~ getSegmentSymbol(segment));
        outFile.writeln("D=D+M"); 
        outFile.writeln("@R13");
        outFile.writeln("M=D");

        // שליפת האיבר העליון והכנסתו לכתובת השמורה ב-R13
        popToD();
        outFile.writeln("@R13");
        outFile.writeln("A=M");
        outFile.writeln("M=D");
    } 
    else if (segment == "temp") {
        int addr = 5 + to!int(index);
        popToD();
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("M=D");
    } 
    else if (segment == "pointer") {
        int addr = 3 + to!int(index);
        popToD();
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("M=D");
    } 
    else if (segment == "static") {
        popToD();
        outFile.writeln("@" ~ currentFileName ~ "." ~ index);
        outFile.writeln("M=D");
    }
}

// פונקציית עזר למשיכת איבר מהמחסנית אל רגיסטר D
void popToD() {
    outFile.writeln("@SP");
    outFile.writeln("AM=M-1");
    outFile.writeln("D=M");
}

// פונקציית עזר להמרת שם סגמנט לסימבול ה-HACK שלו
string getSegmentSymbol(string segment) {
    switch(segment) {
        case "local": return "LCL";
        case "argument": return "ARG";
        case "this": return "THIS";
        case "that": return "THAT";
        default: return "";
    }
}