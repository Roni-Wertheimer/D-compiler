import std.stdio;
import std.string;
import std.path;
import std.file;
import std.array;
import std.conv;

// משתנים גלובאליים
string currentFileName;
string currentFunctionName = ""; // שומר את שם הפונקציה הנוכחית כדי לייצר תוויות ייחודיות
File outFile;
int logicCounter = 0; 
int callCounter = 0; // מונה לייצור תוויות חזרה ייחודיות עבור פונקציות

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

    // בדיקה חכמה: האם להוסיף קוד אתחול? (רק אם יש פונקציית Sys.init)
    bool needsBootstrap = exists(buildPath(dirPath, "Sys.vm"));
    if (needsBootstrap) {
        writeInit();
    }

    foreach (string entry; dirEntries(dirPath, "*.vm", SpanMode.shallow)) {
        currentFileName = baseName(entry, ".vm");
        File inFile = File(entry, "r");

        foreach (line; inFile.byLine()) {
            string cleanLine = line.idup;
            
            auto commentPos = cleanLine.indexOf("//");
            if (commentPos != -1) {
                cleanLine = cleanLine[0 .. commentPos];
            }
            
            auto words = cleanLine.split(); 
            if (words.length == 0) continue; 

            string command = words[0];

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

                // בקרת זרימה (Branching)
                case "label":
                    if (words.length >= 2) handleLabel(words[1]);
                    break;
                case "goto":
                    if (words.length >= 2) handleGoto(words[1]);
                    break;
                case "if-goto":
                    if (words.length >= 2) handleIfGoto(words[1]);
                    break;

                // פונקציות (Functions)
                case "function":
                    if (words.length >= 3) handleFunction(words[1], words[2]);
                    break;
                case "call":
                    if (words.length >= 3) handleCall(words[1], words[2]);
                    break;
                case "return":
                    handleReturn();
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
// פונקציות עזר 
// ==========================================

void writeInit() {
    outFile.writeln("// Bootstrapping");
    outFile.writeln("@256");
    outFile.writeln("D=A");
    outFile.writeln("@SP");
    outFile.writeln("M=D");
    handleCall("Sys.init", "0");
}

string formatLabel(string label) {
    if (currentFunctionName.length > 0) {
        return currentFunctionName ~ "$" ~ label;
    }
    return label;
}

void pushD() {
    outFile.writeln("@SP");
    outFile.writeln("A=M");
    outFile.writeln("M=D");
    outFile.writeln("@SP");
    outFile.writeln("M=M+1");
}

void popToD() {
    outFile.writeln("@SP");
    outFile.writeln("AM=M-1");
    outFile.writeln("D=M");
}

// --- אריתמטיקה ולוגיקה ---

void handleArithmetic(string op) {
    outFile.writeln("@SP");
    outFile.writeln("AM=M-1"); 
    outFile.writeln("D=M");
    outFile.writeln("A=A-1");  
    outFile.writeln(op);       
}

void handleUnary(string op) {
    outFile.writeln("@SP");
    outFile.writeln("A=M-1"); 
    outFile.writeln(op);      
}

void handleCompare(string jumpType) {
    string labelTrue = "IF_TRUE_" ~ to!string(logicCounter);
    string labelEnd = "IF_END_" ~ to!string(logicCounter);
    logicCounter++;

    outFile.writeln("@SP");
    outFile.writeln("AM=M-1");
    outFile.writeln("D=M");     
    outFile.writeln("A=A-1");
    outFile.writeln("D=M-D");   

    outFile.writeln("@" ~ labelTrue);
    outFile.writeln("D;" ~ jumpType); 

    outFile.writeln("@SP");     
    outFile.writeln("A=M-1");
    outFile.writeln("M=0");     
    outFile.writeln("@" ~ labelEnd);
    outFile.writeln("0;JMP");

    outFile.writeln("(" ~ labelTrue ~ ")");
    outFile.writeln("@SP");     
    outFile.writeln("A=M-1");
    outFile.writeln("M=-1");    

    outFile.writeln("(" ~ labelEnd ~ ")");
}

// --- גישה לזיכרון ---

void handlePush(string segment, string index) {
    if (segment == "constant") {
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
    } 
    else if (segment == "local" || segment == "argument" || segment == "this" || segment == "that") {
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
        outFile.writeln("@" ~ getSegmentSymbol(segment));
        outFile.writeln("D=D+M"); 
        outFile.writeln("A=D");   
        outFile.writeln("D=M");   
    } 
    else if (segment == "temp") {
        int addr = 5 + to!int(index);
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("D=M");
    } 
    else if (segment == "pointer") {
        int addr = 3 + to!int(index); 
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("D=M");
    } 
    else if (segment == "static") {
        outFile.writeln("@" ~ currentFileName ~ "." ~ index);
        outFile.writeln("D=M");
    }
    pushD();
}

void handlePop(string segment, string index) {
    if (segment == "local" || segment == "argument" || segment == "this" || segment == "that") {
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
        outFile.writeln("@" ~ getSegmentSymbol(segment));
        outFile.writeln("D=D+M"); 
        outFile.writeln("@R13");
        outFile.writeln("M=D");

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

string getSegmentSymbol(string segment) {
    switch(segment) {
        case "local": return "LCL";
        case "argument": return "ARG";
        case "this": return "THIS";
        case "that": return "THAT";
        default: return "";
    }
}

// --- בקרת זרימה (Branching) ---

void handleLabel(string label) {
    outFile.writeln("(" ~ formatLabel(label) ~ ")");
}

void handleGoto(string label) {
    outFile.writeln("@" ~ formatLabel(label));
    outFile.writeln("0;JMP");
}

void handleIfGoto(string label) {
    popToD();
    outFile.writeln("@" ~ formatLabel(label));
    outFile.writeln("D;JNE"); // קופץ אם הערך שונה מ-0 (True)
}

// --- פונקציות (Functions) ---

void handleFunction(string functionName, string numVars) {
    currentFunctionName = functionName;
    outFile.writeln("(" ~ functionName ~ ")");
    
    int k = to!int(numVars);
    for (int i = 0; i < k; i++) {
        outFile.writeln("@0");
        outFile.writeln("D=A");
        pushD();
    }
}

void handleCall(string functionName, string numArgs) {
    string retLabel = "RETURN_" ~ functionName ~ "_" ~ to!string(callCounter++);
    
    // push return-address
    outFile.writeln("@" ~ retLabel);
    outFile.writeln("D=A");
    pushD();
    
    // push LCL, ARG, THIS, THAT
    string[] segments = ["LCL", "ARG", "THIS", "THAT"];
    foreach(seg; segments) {
        outFile.writeln("@" ~ seg);
        outFile.writeln("D=M");
        pushD();
    }
    
    // ARG = SP - n - 5
    outFile.writeln("@SP");
    outFile.writeln("D=M");
    outFile.writeln("@" ~ numArgs);
    outFile.writeln("D=D-A");
    outFile.writeln("@5");
    outFile.writeln("D=D-A");
    outFile.writeln("@ARG");
    outFile.writeln("M=D");
    
    // LCL = SP
    outFile.writeln("@SP");
    outFile.writeln("D=M");
    outFile.writeln("@LCL");
    outFile.writeln("M=D");
    
    // goto f
    outFile.writeln("@" ~ functionName);
    outFile.writeln("0;JMP");
    
    // (return-address)
    outFile.writeln("(" ~ retLabel ~ ")");
}

void handleReturn() {
    // FRAME = LCL (שמירה ב-R13)
    outFile.writeln("@LCL");
    outFile.writeln("D=M");
    outFile.writeln("@R13");
    outFile.writeln("M=D");

    // RET = *(FRAME-5) (שמירה ב-R14)
    outFile.writeln("@5");
    outFile.writeln("A=D-A");
    outFile.writeln("D=M");
    outFile.writeln("@R14");
    outFile.writeln("M=D");

    // *ARG = pop()
    popToD();
    outFile.writeln("@ARG");
    outFile.writeln("A=M");
    outFile.writeln("M=D");

    // SP = ARG+1
    outFile.writeln("@ARG");
    outFile.writeln("D=M+1");
    outFile.writeln("@SP");
    outFile.writeln("M=D");

    // THAT = *(FRAME-1)
    outFile.writeln("@R13");
    outFile.writeln("A=M-1");
    outFile.writeln("D=M");
    outFile.writeln("@THAT");
    outFile.writeln("M=D");

    // THIS = *(FRAME-2)
    outFile.writeln("@R13");
    outFile.writeln("D=M");
    outFile.writeln("@2");
    outFile.writeln("A=D-A");
    outFile.writeln("D=M");
    outFile.writeln("@THIS");
    outFile.writeln("M=D");

    // ARG = *(FRAME-3)
    outFile.writeln("@R13");
    outFile.writeln("D=M");
    outFile.writeln("@3");
    outFile.writeln("A=D-A");
    outFile.writeln("D=M");
    outFile.writeln("@ARG");
    outFile.writeln("M=D");

    // LCL = *(FRAME-4)
    outFile.writeln("@R13");
    outFile.writeln("D=M");
    outFile.writeln("@4");
    outFile.writeln("A=D-A");
    outFile.writeln("D=M");
    outFile.writeln("@LCL");
    outFile.writeln("M=D");

    // goto RET
    outFile.writeln("@R14");
    outFile.writeln("A=M");
    outFile.writeln("0;JMP");
}