/*
 Aharon wertheimer 206447773
 Moshe shushan 316314731
*/

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.array;
import std.conv; // For converting numbers to strings

// Global variables
string currentFileName;
File outFile;
int logicCounter = 0; // Counter for generating unique jump labels

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
            
            // Strip comments from the line (if any)
            auto commentPos = cleanLine.indexOf("//");
            if (commentPos != -1) {
                cleanLine = cleanLine[0 .. commentPos];
            }
            
            auto words = cleanLine.split(); 
            if (words.length == 0) continue; // Skip empty lines

            string command = words[0];

            // Write a comment in the asm file for readability and debugging
            outFile.writeln("// " ~ cleanLine.strip());

            switch(command) {
                // Arithmetic and Logic
                case "add": handleArithmetic("M=D+M"); break;
                case "sub": handleArithmetic("M=M-D"); break;
                case "and": handleArithmetic("M=D&M"); break;
                case "or":  handleArithmetic("M=D|M"); break;
                case "neg": handleUnary("M=-M"); break;
                case "not": handleUnary("M=!M"); break;
                case "eq":  handleCompare("JEQ"); break;
                case "gt":  handleCompare("JGT"); break;
                case "lt":  handleCompare("JLT"); break;
                
                // Memory Access
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



//Arithmetic and Logic 

void handleArithmetic(string op) {
    outFile.writeln("@SP");
    outFile.writeln("AM=M-1"); // y
    outFile.writeln("D=M");
    outFile.writeln("A=A-1");  // x
    outFile.writeln(op);       // Perform the operation
}

void handleUnary(string op) {
    outFile.writeln("@SP");
    outFile.writeln("A=M-1"); // Access the top element without changing SP
    outFile.writeln(op);      // Perform the operation
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
    outFile.writeln("D;" ~ jumpType); // Jump if condition is met

    outFile.writeln("@SP");     // False case
    outFile.writeln("A=M-1");
    outFile.writeln("M=0");     // 0 represents False
    outFile.writeln("@" ~ labelEnd);
    outFile.writeln("0;JMP");

    outFile.writeln("(" ~ labelTrue ~ ")");
    outFile.writeln("@SP");     // True case
    outFile.writeln("A=M-1");
    outFile.writeln("M=-1");    // -1 represents True

    outFile.writeln("(" ~ labelEnd ~ ")");
}

//  Memory Access (Push/Pop)

void handlePush(string segment, string index) {
    if (segment == "constant") {
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
    } 
    else if (segment == "local" || segment == "argument" || segment == "this" || segment == "that") {
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
        outFile.writeln("@" ~ getSegmentSymbol(segment));
        outFile.writeln("D=D+M"); // Critical fix: Calculate target address into D instead of A
        outFile.writeln("A=D");   // Move the safe address to A
        outFile.writeln("D=M");   // Read the requested value
    } 
    else if (segment == "temp") {
        int addr = 5 + to!int(index);
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("D=M");
    } 
    else if (segment == "pointer") {
        int addr = 3 + to!int(index); // 3 is THIS, 4 is THAT
        outFile.writeln("@" ~ to!string(addr));
        outFile.writeln("D=M");
    } 
    else if (segment == "static") {
        outFile.writeln("@" ~ currentFileName ~ "." ~ index);
        outFile.writeln("D=M");
    }

    // Push the value in D onto the stack and increment SP
    outFile.writeln("@SP");
    outFile.writeln("A=M");
    outFile.writeln("M=D");
    outFile.writeln("@SP");
    outFile.writeln("M=M+1");
}

void handlePop(string segment, string index) {
    if (segment == "local" || segment == "argument" || segment == "this" || segment == "that") {
        // Calculate target address and save it in temporary register R13
        outFile.writeln("@" ~ index);
        outFile.writeln("D=A");
        outFile.writeln("@" ~ getSegmentSymbol(segment));
        outFile.writeln("D=D+M"); 
        outFile.writeln("@R13");
        outFile.writeln("M=D");

        // Pop the top element and store it in the address held in R13
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

// Helper function to pop element from stack into D register
void popToD() {
    outFile.writeln("@SP");
    outFile.writeln("AM=M-1");
    outFile.writeln("D=M");
}

// Helper function to convert segment name to its HACK symbol
string getSegmentSymbol(string segment) {
    switch(segment) {
        case "local": return "LCL";
        case "argument": return "ARG";
        case "this": return "THIS";
        case "that": return "THAT";
        default: return "";
    }
}