//+------------------------------------------------------------------+
//|                                Bullish and Bearish Engulfing.mq5 |
//|                              Copyright © 2017, Vladimir Karputov |
//|                                           http://wmua.ru/slesar/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2019, Fernando Dias"
#property link      "http://wmua.ru/slesar/"
#property version   "1.005"
#property description "Bullish and Bearish Engulfing"
//---
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>  
#include <Expert\Money\MoneyFixedMargin.mqh>
#include <ArraySequence.mqh>
#include <Logger.mqh>
#include <JAson.mqh>

CPositionInfo      m_position;                   // trade position object
CTrade             m_trade;                      // trading object
CSymbolInfo        m_symbol;                     // symbol info object
CAccountInfo       m_account;                    // account info wrapper
CMoneyFixedMargin  m_money;


//------------------------------ Paramêtros de Entrada ------------------------

input int                  quantidadeContratos      = 1;
input bool                 desconsideraPrimeiroEngolfo = false;
input string inicio="09:30"; //Horario de inicio(entradas);
input string termino="17:00"; //Horario de termino(entradas);
input string fechamento="17:30"; //Horario de fechamento(entradas abertas);
input int      riscoMaximoPontos           = 450;
input int      riscoMinimoPontos           = 100;
input int      limtePontosPrimeiraOperacao = 300;
input int      pontosAcumuladosMes         = 700;

//------------------------------ Paramêtros Gerais  ------------------------


int      primeiroEngolfo             = 0;
ulong    m_magic                     = 270656512;      

string   versao                      = "v1_11072019_2035";      


MqlDateTime horario_inicio,horario_termino,horario_fechamento,horario_atual;
//---
ulong                      desvioPermitido =10;                               // slippage
bool                       trade_ativo = false;
bool                       trade_ativo_mes = false;

objvector<Sequencia> sequencias;

void InitLogger()
  {

//--- DEBUG-nível (nível de depuração) para registrar o as mensagens no arquivo de log
//--- ERROR-nível para notificações
   CLogger::SetLevels(LOG_LEVEL_DEBUG,LOG_LEVEL_ERROR);
//--- definir o tipo de notificações como notificações por push
   CLogger::SetNotificationMethod(NOTIFICATION_METHOD_PUSH);
//--- definir o método de registro em log para registrar em um arquivo externo
   CLogger::SetLoggingMethod(LOGGING_OUTPUT_METHOD_EXTERN_FILE);
//--- definir o nome dos arquivos de log
   CLogger::SetLogFileName("meta");
//--- obter o tipo de restrição para o arquivo de log como "novo arquivo de log para cada novo dia"
   CLogger::SetLogFileLimitType(LOG_FILE_LIMIT_TYPE_ONE_DAY);
  }



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

   InitLogger();
   
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - Quantidade Contratos: %s", IntegerToString(quantidadeContratos)));
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - inicio: %s", inicio));
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - termino: %s", termino));
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - fechamento: %s", fechamento));
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - riscoMaximoPontos: %s", IntegerToString(riscoMaximoPontos)));
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - riscoMinimoPontos: %s", IntegerToString(riscoMinimoPontos)));
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - limtePontosPrimeiraOperacao: %s", IntegerToString(limtePontosPrimeiraOperacao)));
   LOG(LOG_LEVEL_INFO, StringFormat("Parametros entrada - pontosAcumuladosMes: %s", IntegerToString(pontosAcumuladosMes)));
   
   if( quantidadeContratos==0 || quantidadeContratos > 5) {
       LOG(LOG_LEVEL_ERROR, StringFormat("Quantidade de contratos inválidos: %s", IntegerToString(quantidadeContratos)));
       return(INIT_PARAMETERS_INCORRECT);
   }
   
   TimeToStruct(StringToTime(inicio),horario_inicio);         //+-------------------------------------+
   TimeToStruct(StringToTime(termino),horario_termino);       //| Conversão das variaveis para mql    |
   TimeToStruct(StringToTime(fechamento),horario_fechamento); //+-------------------------------------+
   
   if(horario_inicio.hour>horario_termino.hour || 
     (horario_inicio.hour==horario_termino.hour && horario_inicio.min>horario_termino.min)) {
      LOG(LOG_LEVEL_ERROR, "Parametros de data inválidos");
      return INIT_PARAMETERS_INCORRECT;
   }
     
   if(horario_termino.hour>horario_fechamento.hour || 
      (horario_termino.hour==horario_fechamento.hour && horario_termino.min>horario_fechamento.min)){
      LOG(LOG_LEVEL_ERROR, "Parametros de data inválidos");
      return INIT_PARAMETERS_INCORRECT;
   }
   
  
 
   InformacaoConta();
   
   m_symbol.Name(Symbol());                 
   Print("Simbolo nome =",m_symbol.Name());
   RefreshRates();
   m_symbol.Refresh();

   m_trade.SetExpertMagicNumber(m_magic);

   // Forma de preencher ordens com volume.
   if(IsFillingTypeAllowed(Symbol(),SYMBOL_FILLING_FOK))
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if(IsFillingTypeAllowed(Symbol(),SYMBOL_FILLING_IOC))
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   //--- Desvio Permitido--------------
   m_trade.SetDeviationInPoints(desvioPermitido);
   
   
   LOG(LOG_LEVEL_INFO, "Trade ativo = true");
   trade_ativo = true;
   trade_ativo_mes = true;
   primeiroEngolfo = 0;
   sequencias.Clear();
   
   
     
   double historicoPontosMes = HistoricoMensal();
   eventoSetup(historicoPontosMes);
    
   return(INIT_SUCCEEDED);
   
  }
  
  void eventoSetup(double pontosAcumulados) {
  
      CAccountInfo account;
      long login=account.Login();
  
      CJAVal jv;
      jv["contaMetaTrader"]=DoubleToString(login,0); 
      long saldo = NormalizeDouble(account.Balance(),2); 
      jv["saldo"]=DoubleToString(saldo,2);
      jv["versao"]= versao;
      
      string flag;
      if (trade_ativo_mes) {
        flag = "true";
      } else {
        flag = "false";
      }
      jv["ativoMensal"]=flag;
      jv["pontosAcumuladosMes"]=DoubleToString(pontosAcumulados,2);
      
      
      
      char data[]; 
      ArrayResize(data, StringToCharArray(jv.Serialize(), data, 0, WHOLE_ARRAY)-1);
      char res_data[];
     
      string res_headers=NULL;
      int res=WebRequest("POST", "http://youbankfollowup-env.ehvbkbits4.us-east-1.elasticbeanstalk.com/api/v1/eventoStart", "Content-Type: application/json\r\n", 2000, data, res_data, res_headers);
   
      if (res == -1) {
        LOG(LOG_LEVEL_INFO, StringFormat("Erro integracao - Tipo da Conta: Login: %s - Erro: %s",DoubleToString(login),IntegerToString(GetLastError())));
     
      }
   
  }
  
  void eventoResultadoPosicao(string simbolo, double volume, string tipo, ulong ticket, double resultado, uint statusOperacao, ulong posicao, string operacao) {
      string out;
   
      CAccountInfo account;
      long login=account.Login();
  
      CJAVal jv;
      jv["contaMetaTrader"]=DoubleToString(login,0); 
      jv["simbolo"]=simbolo;
      jv["volume"]=DoubleToString(volume,0);
      jv["tipo"]=tipo;
      jv["ticket"]=DoubleToString(ticket,0);
      //jv["posicao"]=DoubleToString(posicao,0);
      //jv["operacao"]=operacao;
      jv["statusOperacao"]=IntegerToString(statusOperacao);
      jv["resultado"]=DoubleToString(resultado,2); 
      
      out=""; jv.Serialize(out,false);
      Print(out);
            
      char data[]; 
      ArrayResize(data, StringToCharArray(jv.Serialize(), data, 0, WHOLE_ARRAY)-1);
      char res_data[];
     
      string res_headers=NULL;
      int res=WebRequest("POST", "http://youbankfollowup-env.ehvbkbits4.us-east-1.elasticbeanstalk.com/api/v1/eventoResultadoPosicao", "Content-Type: application/json\r\n", 2000, data, res_data, res_headers);
   
      if (res == -1) {
        LOG(LOG_LEVEL_INFO, StringFormat("Erro integracao Evento Resultado Posicao - Tipo da Conta: Login: %s - Erro: %s",DoubleToString(login),IntegerToString(GetLastError())));
     
      }
  
  }
  
  void InformacaoConta() {
 
   CAccountInfo account;
   long login=account.Login();
  
   ENUM_ACCOUNT_TRADE_MODE account_type=account.TradeMode();
   LOG(LOG_LEVEL_INFO, StringFormat("Tipo da Conta: Login: %s - Tipo: %s",DoubleToString(login),EnumToString(account_type)));
   
   if(account.TradeAllowed())
      LOG(LOG_LEVEL_INFO, StringFormat("Trading está permitido para essa conta: Login: %s",DoubleToString(login)));
   else
      LOG(LOG_LEVEL_INFO, StringFormat("Tranding não permitido para conta: Login: %s",DoubleToString(login)));

   if(account.TradeExpert())
      LOG(LOG_LEVEL_INFO, StringFormat("Tranding Automático autorizado para conta: Login: %s",DoubleToString(login)));
   else
      LOG(LOG_LEVEL_INFO, StringFormat("Tranding Automático não autorizado para conta: Login: %s",DoubleToString(login)));
      
  int orders_limit=account.LimitOrders();
   if(orders_limit!=0)
     LOG(LOG_LEVEL_INFO, StringFormat("Limite de ordens pendentes para conta: Login: %s - Limite Ordens: %s",DoubleToString(login),orders_limit));
      
   LOG(LOG_LEVEL_INFO, StringFormat("Servidor: %s - Login: %s - Saldo: %s",account.Server(),DoubleToString(login),DoubleToString(account.Balance())));
   
   Print("Balance=",account.Balance(),"  Profit=",account.Profit(),"   Equity=",account.Equity());

  }
  

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---

  }
  
void backTeste() {

   static datetime PreBars=0;
   static datetime PreBarsMon=0;
   
   
   datetime time_0=iTime(m_symbol.Name(),PERIOD_D1,0);
   
   datetime time_m=iTime(m_symbol.Name(),PERIOD_MN1,0);
   
   if(time_0!=PreBars){
      trade_ativo = true;
      primeiroEngolfo = 0;
      sequencias.Clear();
   }
   
   if (time_m!=PreBarsMon) {
      trade_ativo_mes = true;
   } 
   
   PreBars=time_0;
   PreBarsMon = time_m;



}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  
   //backTeste();
     
   static datetime PrevBars=0;
   datetime time_0=iTime(m_symbol.Name(),Period(),0);
   if(time_0==PrevBars)
      return;
   PrevBars=time_0;
 
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int start_pos=1;
   int copied=CopyRates(m_symbol.Name(),Period(),start_pos,2,rates);
   
   if(HorarioFechamento()) {
      ClosePositions();
      LOG(LOG_LEVEL_INFO, "Posição aberta deletada, limite de horário");
   }
   
   if(copied==2)
     {
           
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         if(OrderGetTicket(i) > 0) {
            m_trade.OrderDelete(OrderGetTicket(i));
            LOG(LOG_LEVEL_INFO, "Ordem pendente deletada, preço alvo não atingido");
         }
      }
      
    for(int i=PositionsTotal()-1;i>=0;i--) {// returns the number of current orders
      if(m_position.SelectByIndex(i)) {    // selects the position by index for further access to its properties
         
         if(HorarioFechamento()) {
             ClosePositions();
             LOG(LOG_LEVEL_INFO, "Posição aberta deletada, limite de horário");
             return;
         }
         
         if(m_position.Symbol()==m_symbol.Name())
           return;
      }   
    }  
      
      double max_serie = 0.0;
      double min_serie = 0.0;
      double diff_serie = 0.0;
      if (rates[0].high > rates[1].high) 
      {
        max_serie = rates[0].high;
      } else {
        max_serie = rates[1].high;
      }
      
      if (rates[0].low < rates[1].low) 
      {
        min_serie = rates[0].low;
      } else {
        min_serie = rates[1].low;
      }
      
      diff_serie = max_serie - min_serie;
      
      if(rates[0].open<rates[0].close && rates[1].open>rates[1].close)  // Candle recente de alta e Candle anterior de baixa
        {
          double cl_recente = rates[0].close - rates[0].open;
          double cl_anterior = rates[1].open - rates[1].close;
          Print("Recente= ",cl_recente,"Anterior= ",cl_anterior,"Resultado= ", cl_recente > cl_anterior);
          bool enf_alta = cl_recente > cl_anterior;
          Print("Engolfo de alta ", enf_alta);
          
          if(enf_alta )
            {
              Print("Max,Min= ",max_serie - min_serie);
             
              if ((diff_serie <= riscoMaximoPontos) && (diff_serie >= riscoMinimoPontos))  
                {
                  Print("Operacao de compra");
                  Print("Stop loss=",min_serie,"Stop Gain=",max_serie + diff_serie);
                                   
                   if (trade_ativo && trade_ativo_mes) {
                     if (HorarioRoboteste()) {
                        primeiroEngolfo++;
                        if (desconsideraPrimeiroEngolfo) {
                           if ( primeiroEngolfo>1)
                              OpenBuyStop(quantidadeContratos ,m_symbol.Name(),max_serie,min_serie,max_serie + diff_serie);
                        } else {
                              OpenBuyStop(quantidadeContratos ,m_symbol.Name(),max_serie,min_serie,max_serie + diff_serie);
                        }
                     }
                   }
                }
            }
         }
         
       if(rates[0].open>rates[0].close && rates[1].open<rates[1].close)  // Candle recente de baixa e Candle anterior de alta
         {
          double cl_recente = rates[0].open - rates[0].close;
          double cl_anterior = rates[1].close - rates[1].open;
          Print("Recente= ",cl_recente,"Anterior= ",cl_anterior,"Resultado= ", cl_recente > cl_anterior);
          bool enf_baixa = cl_recente > cl_anterior;
          Print("Engolfo de baixa ", enf_baixa);
          
          if(enf_baixa )
            {
              Print("Max,Min= ",max_serie - min_serie);
              if ((diff_serie <= riscoMaximoPontos) && (diff_serie >= riscoMinimoPontos))  
                {
                  Print("Operacao de Venda");
                  Print("Stop loss=",max_serie,"Stop Gain=",min_serie - diff_serie);
                  
                  if (trade_ativo && trade_ativo_mes) {
                    if (HorarioRoboteste()) {
                       primeiroEngolfo++;
                       if (desconsideraPrimeiroEngolfo) {
                          if ( primeiroEngolfo>1)
                             OpenSellStop(quantidadeContratos,m_symbol.Name(),min_serie,max_serie,min_serie - diff_serie);
                        } 
                        else {
                            OpenSellStop(quantidadeContratos,m_symbol.Name(),min_serie,max_serie,min_serie - diff_serie);
                       }
                     }
                  }
                }
            }
          }
     }
   else
     {
      PrevBars=iTime(m_symbol.Name(),Period(),1);
      Print("Failed to get history data for the symbol ",Symbol());
     }

   return;
  }

//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates()
  {
//--- refresh rates
   if(!m_symbol.RefreshRates())
      return(false);
//--- protection against the return value of "zero"
   if(m_symbol.Ask()==0 || m_symbol.Bid()==0)
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+ 
//| Checks if the specified filling mode is allowed                  | 
//+------------------------------------------------------------------+ 
bool IsFillingTypeAllowed(string symbol,int fill_type)
  {
//--- Obtain the value of the property that describes allowed filling modes 
   int filling=(int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   Print("Simbolo filling = ", filling);
//--- Return true, if mode fill_type is allowed 
   return((filling & fill_type)==fill_type);
  }
//+------------------------------------------------------------------+
//| Close Positions                                                  |
//+------------------------------------------------------------------+
void ClosePositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--) // returns the number of current orders
      if(m_position.SelectByIndex(i))     // selects the position by index for further access to its properties
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==m_magic)
            if (m_trade.PositionClose(m_position.Ticket()))
               LOG(LOG_LEVEL_INFO, StringFormat("Fechando posição: %s",IntegerToString(m_trade.ResultRetcode())));
  }

datetime DataInicioMes(datetime data)  {
   MqlDateTime dt;
   TimeToStruct(data,dt);
   dt.day  = 1;
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return(StructToTime(dt));
}  

double HistoricoMensalAnterior() {
   double  pontos_acumulados = 0;
   string simbolo;
   datetime mon = DataInicioMes(TimeCurrent());
    
   TimeToStruct(StringToTime(termino),horario_termino);
    
   HistorySelect(mon,StructToTime(horario_termino)); 
   uint total=HistoryDealsTotal(); 
   for(uint i=0;i<total;i++) 
     { 
          ulong ticketAtual = HistoryDealGetTicket(i);
          ulong ticketAnterior = HistoryDealGetTicket(i-1);
          simbolo = "";
          simbolo = HistoryDealGetString(ticketAtual,DEAL_SYMBOL);
          //LOG(LOG_LEVEL_INFO,StringFormat("Simbol",simbolo));   
          if((ticketAtual >0 && ticketAnterior > 0) && (StringSubstr(simbolo,0,3)=="WIN")) {
             long entryAtual = HistoryDealGetInteger(ticketAtual,DEAL_ENTRY);  
             
             if (entryAtual==DEAL_ENTRY_OUT) {
                 double priceAtual    = HistoryDealGetDouble(ticketAtual,DEAL_PRICE);
                 double profitAtual  = HistoryDealGetDouble(ticketAtual,DEAL_PROFIT); 
                 
                 double priceAnterior = HistoryDealGetDouble(ticketAnterior,DEAL_PRICE);
                
                 double resultado = priceAtual - priceAnterior;
                 LOG(LOG_LEVEL_INFO, StringFormat("Preco atual: %s - Preco anterior: %s - resultado: %s - Profit: %s",
                  DoubleToString(priceAtual),DoubleToString(priceAnterior),DoubleToString(pontos_acumulados),DoubleToString(profitAtual)));
                   
                 if (profitAtual > 0) {
                    pontos_acumulados += MathAbs(resultado); 
                    Print("Pontos acumulados no mês-->",pontos_acumulados);
                 } else if(profitAtual < 0) {
                    pontos_acumulados -= MathAbs(resultado); 
                    Print("Pontos acumulados no mês-->",pontos_acumulados);
                }
                 //Limite de pontos ganhos no mês
                if (pontos_acumulados >= pontosAcumuladosMes) {
                   trade_ativo_mes = false;
                   LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos mês atingido: %s",DoubleToString(pontos_acumulados)));
                } else {
                   trade_ativo_mes = true;
                }
            }
         }
     }
    LOG(LOG_LEVEL_INFO, StringFormat("Pontos acumlados mês: %s", DoubleToString(pontos_acumulados)));
    LOG(LOG_LEVEL_INFO, StringFormat("Resumo Operação - Continuar operando diário: %s - Mensal: %s" ,IntegerToString(trade_ativo),IntegerToString(trade_ativo_mes))); 
    return pontos_acumulados;

}

double HistoricoMensal() {
   double  pontos_acumulados = 0;
   uint valorCemPontos = 20;
   double valor = 0;
   double pontos;
   string simbolo;
   datetime mon = DataInicioMes(TimeCurrent());
    
   TimeToStruct(StringToTime(termino),horario_termino);
    
   HistorySelect(mon,StructToTime(horario_termino)); 
   uint total=HistoryDealsTotal(); 
   for(uint i=0;i<total;i++) 
     { 
          ulong ticketAtual = HistoryDealGetTicket(i);
          ulong ticketAnterior = HistoryDealGetTicket(i-1);
          simbolo = "";
          simbolo = HistoryDealGetString(ticketAtual,DEAL_SYMBOL);
          string simboloWin = StringSubstr(simbolo,0,3);
          if((ticketAtual >0) && (StringCompare(simboloWin,"WIN",false)==0)) {
             long entryAtual = HistoryDealGetInteger(ticketAtual,DEAL_ENTRY);  
             
             if (entryAtual==DEAL_ENTRY_OUT) {
                 double profitAtual  = HistoryDealGetDouble(ticketAtual,DEAL_PROFIT); 
                 
                 valor = 0;
                 pontos = 0;  
                 if (profitAtual > 0) {
                    valor = (MathAbs(profitAtual)/quantidadeContratos);
                    pontos = NormalizeDouble((valor/valorCemPontos)*100,0);
                    pontos_acumulados +=pontos; 
                    LOG(LOG_LEVEL_INFO, StringFormat("Lucro: %s - Pontos: %s", DoubleToString(profitAtual),DoubleToString(pontos)));
           
                 } else if(profitAtual < 0) {
                    valor = (MathAbs(profitAtual)/quantidadeContratos);
                    pontos = NormalizeDouble((valor/valorCemPontos)*100,0);
                    pontos_acumulados -= pontos; 
                    LOG(LOG_LEVEL_INFO, StringFormat("Prejuizo: %s - Pontos: %s", DoubleToString(profitAtual), DoubleToString(pontos)));
                   
                }
                 //Limite de pontos ganhos no mês
                if (pontos_acumulados >= pontosAcumuladosMes) {
                   trade_ativo_mes = false;
                   LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos mês atingido: %s",DoubleToString(pontos_acumulados)));
                } else {
                   trade_ativo_mes = true;
                }
            }
         }
     }
    LOG(LOG_LEVEL_INFO, StringFormat("Pontos acumlados mês: %s", DoubleToString(pontos_acumulados)));
    LOG(LOG_LEVEL_INFO, StringFormat("Resumo Operação - Continuar operando diário: %s - Mensal: %s" ,IntegerToString(trade_ativo),IntegerToString(trade_ativo_mes))); 
    return pontos_acumulados;

}

void HistoricoDiario() {
  
   double  pontos_acumulados = 0;
   uint valorCemPontos = 20;
   double valor = 0;
   double pontos;
   
   
   string  simbolo;
        
   TimeToStruct(StringToTime(inicio),horario_inicio);     
   TimeToStruct(StringToTime(termino),horario_termino);
   
  
   HistorySelect(StructToTime(horario_inicio),StructToTime(horario_termino)); 
   uint total=HistoryDealsTotal(); 
   for(uint i=0;i<total;i++){ 
      
      ulong ticket = HistoryDealGetTicket(i);
      simbolo = "";
      simbolo = HistoryDealGetString(ticket,DEAL_SYMBOL);
      
      string simboloWin = StringSubstr(simbolo,0,3);
    
      if ( StringCompare(simboloWin,"WIN",false)==0) { 
      //Calculo pontos somente na sáída da posição 
         if (MathMod(total,2) == 0) {
                      
             ulong ticketAtual = HistoryDealGetTicket(i);
            
             if(ticketAtual >0) {
                long entryAtual = HistoryDealGetInteger(ticketAtual,DEAL_ENTRY);  
                
                if (entryAtual==DEAL_ENTRY_OUT) {
                    double profitAtual  = HistoryDealGetDouble(ticketAtual,DEAL_PROFIT); 
                    valor = 0;
                    pontos = 0; 
                    if (profitAtual > 0) {
                 
                       
                       valor = (MathAbs(profitAtual)/quantidadeContratos);
                       pontos = (valor/valorCemPontos)*100;
                     
                       pontos_acumulados += NormalizeDouble(pontos,0); 
                       if (MathAbs(pontos) > limtePontosPrimeiraOperacao && total==2) {
                          trade_ativo = false;
                          LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos antigido primeira operação: %s", 
                             DoubleToString(MathAbs(NormalizeDouble(pontos,0)))));
                       }
                    } else if(profitAtual < 0) {
                                              
                       valor = (MathAbs(profitAtual)/quantidadeContratos);
                       pontos = (valor/valorCemPontos)*100;
                       
                       pontos_acumulados -= NormalizeDouble(pontos,0); 
                    
                    }
                    //Limite de pontos ganhos no dia
                    if (pontos_acumulados >= 450) {
                        trade_ativo = false;
                        LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos positivos do dia antigido: %s", 
                             DoubleToString(pontos_acumulados)));
                    }
                    
                     //Limite de pontos perdidos no dia
                    if ( pontos_acumulados <=  -450) {
                        trade_ativo = false;
                        LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos negativos do dia antigido: %s", 
                            DoubleToString(pontos_acumulados)));
                    }
                    
                     LOG(LOG_LEVEL_INFO, StringFormat("Pontos diario operacao: %s - Pontos Acumulados: %s", 
                             DoubleToString(MathAbs(NormalizeDouble(pontos,0))),DoubleToString(MathAbs(NormalizeDouble(pontos_acumulados,0)))));
               }
            }
          }  
        }
     }
         
     LOG(LOG_LEVEL_INFO, StringFormat("Resumo Operação - Continuar operando diário: %s - Mensal: %s" ,IntegerToString(trade_ativo),IntegerToString(trade_ativo_mes)));  
 } 
 
 void HistoricoDiarioAnterior() {
  
   double  pontos_acumulados = 0;
   string  simbolo;
   bool    consecutivos[];
   uint    contador = 0;
      
   TimeToStruct(StringToTime(inicio),horario_inicio);     
   TimeToStruct(StringToTime(termino),horario_termino);
   
  
   HistorySelect(StructToTime(horario_inicio),StructToTime(horario_termino)); 
   uint total=HistoryDealsTotal(); 
   for(uint i=0;i<total;i++){ 
      
      ulong ticket = HistoryDealGetTicket(i);
      simbolo = "";
      simbolo = HistoryDealGetString(ticket,DEAL_SYMBOL);
     
      if ( StringSubstr(simbolo,0,3) == "WIN") { 
      //Calculo pontos somente na sáída da posição 
         if (MathMod(total,2) == 0) {
             ArrayResize(consecutivos,total/2);
         
             ulong ticketAtual = HistoryDealGetTicket(i);
             ulong ticketAnterior = HistoryDealGetTicket(i-1);
           
             if(ticketAtual >0 && ticketAnterior > 0) {
                long entryAtual = HistoryDealGetInteger(ticketAtual,DEAL_ENTRY);  
                
                if (entryAtual==DEAL_ENTRY_OUT) {
                    double priceAtual    = HistoryDealGetDouble(ticketAtual,DEAL_PRICE);
                    double profitAtual  = HistoryDealGetDouble(ticketAtual,DEAL_PROFIT); 
                    double priceAnterior = HistoryDealGetDouble(ticketAnterior,DEAL_PRICE);
                    double resultado = priceAtual - priceAnterior;
                      
                    if (profitAtual > 0) {
                       ArrayFill(consecutivos,contador,1,true);
                       contador++;
                       pontos_acumulados += MathAbs(resultado); 
                       if (MathAbs(resultado) > limtePontosPrimeiraOperacao && total==2) {
                          trade_ativo = false;
                          LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos antigido primeira operação: %s", 
                             DoubleToString(MathAbs(resultado))));
                       }
                    } else if(profitAtual < 0) {
                       ArrayFill(consecutivos,contador,1,false);
                       contador++;
                       pontos_acumulados -= MathAbs(resultado); 
                    
                    }
                    //Limite de pontos ganhos no dia
                    if (pontos_acumulados >= 450) {
                        trade_ativo = false;
                        LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos positivos do dia antigido: %s", 
                             DoubleToString(pontos_acumulados)));
                    }
                    
                     //Limite de pontos perdidos no dia
                    if ( pontos_acumulados <=  -450) {
                        trade_ativo = false;
                        LOG(LOG_LEVEL_INFO, StringFormat("Limite de pontos negativos do dia antigido: %s", 
                            DoubleToString(pontos_acumulados)));
                    }
               }
            }
          }  
        }
     }
     
     // Quantidades consecutivas de ganhos ou perdas 
     for(uint j=0;j<ArraySize(consecutivos);j++) { 
          //Print("array de objetos--> Posicao|",j,"-",consecutivos[j]);  
          // Duas posições consecutivas com ganhos
          if ((j != 0) && (consecutivos[j]==true && consecutivos[j-1]==true)) {
             trade_ativo = false;
             LOG(LOG_LEVEL_INFO, "Sequência de operações com lucro atingido");
          }
           if ((j > 1) && (consecutivos[j]==false && consecutivos[j-1]==false && consecutivos[j-2]==false  )) {
             trade_ativo = false;
             LOG(LOG_LEVEL_INFO, "Sequência de operações com prejuizo atingido");
          }
      }
      
     LOG(LOG_LEVEL_INFO, StringFormat("Resumo Operação - Continuar operando diário: %s - Mensal: %s" ,IntegerToString(trade_ativo),IntegerToString(trade_ativo_mes)));  
 } 


  
  
//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
bool CheckVolumeOrder(double requestVolume,ENUM_ORDER_TYPE orderType ) 
{

  double check = m_trade.CheckVolume(m_symbol.Name(),1,m_symbol.Bid(),orderType);
  return true;
}

void OpenBuyStop(double requestVolume,string symbol, double price, double sl,double sg) 
{
   sl=m_symbol.NormalizePrice(sl);
   sg=m_symbol.NormalizePrice(sg);
   datetime expiration= TimeTradeServer()+PeriodSeconds(PERIOD_M10);
      
   if (CheckVolumeOrder(requestVolume,ORDER_TYPE_BUY_STOP))
   {
      if(!m_trade.BuyStop(requestVolume,price,symbol,sl,sg,ORDER_TIME_GTC,expiration)) {
          LOG(LOG_LEVEL_INFO, StringFormat("Sucesso na operação stop de compra código: %s - Preço: %s - Stop: %s - Gain: %s",
          m_trade.ResultRetcodeDescription(),DoubleToString(price),DoubleToString(sl),DoubleToString(sg)));
      }
      else {
         LOG(LOG_LEVEL_INFO, StringFormat("Sucesso na operação stop de compra %s", m_trade.ResultRetcodeDescription()));
      }
   } 
   else
   {
    LOG(LOG_LEVEL_INFO, StringFormat("Falha na operação stop de compra volume não disponivel %s", DoubleToString(requestVolume)));
    return;
   }
}

void OpenSellStop(double requestVolume,string symbol, double price, double sl,double sg)
{
   sl=m_symbol.NormalizePrice(sl);
   sg=m_symbol.NormalizePrice(sg);
   datetime expiration= TimeTradeServer()+PeriodSeconds(PERIOD_M10);
    
   if (CheckVolumeOrder(requestVolume,ORDER_TYPE_SELL_STOP))
   {
      if(!m_trade.SellStop(requestVolume,price,symbol,sl,sg,ORDER_TIME_GTC,expiration)){
        LOG(LOG_LEVEL_INFO, StringFormat("Falha na operação stop de venda %s", m_trade.ResultRetcodeDescription()));
      }
      else {
         LOG(LOG_LEVEL_INFO, StringFormat("Sucesso na operação stop de venda código: %s - Preço: %s - Stop: %s - Gain: %s",
          m_trade.ResultRetcodeDescription(),DoubleToString(price),DoubleToString(sl),DoubleToString(sg)));
      }
   } 
   else
   {
    LOG(LOG_LEVEL_INFO, StringFormat("Falha na operação stop de venda volume não disponivel %s", DoubleToString(requestVolume)));
    return;
   }
  

}



void OpenBuy(double sl,double tp)
  {
   sl=m_symbol.NormalizePrice(sl);
   tp=m_symbol.NormalizePrice(tp);
   double check_open_long_lot=m_money.CheckOpenLong(m_symbol.Ask(),sl);
//Print("sl=",DoubleToString(sl,m_symbol.Digits()),
//      ", CheckOpenLong: ",DoubleToString(check_open_long_lot,2),
//      ", Balance: ",    DoubleToString(m_account.Balance(),2),
//      ", Equity: ",     DoubleToString(m_account.Equity(),2),
//      ", FreeMargin: ", DoubleToString(m_account.FreeMargin(),2));
   if(check_open_long_lot==0.0)
      return;

//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
   double check_volume_lot= m_trade.CheckVolume(m_symbol.Name(),check_open_long_lot,m_symbol.Ask(),ORDER_TYPE_BUY);

   if(check_volume_lot!=0.0)
      if(check_volume_lot>=check_open_long_lot)
        {
         if(m_trade.Buy(1,NULL,m_symbol.Ask(),sl,tp))
           {
            if(m_trade.ResultDeal()==0)
              {
               Print("Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
                     ", description of result: ",m_trade.ResultRetcodeDescription());
              }
            else
              {
               Print("Buy -> true. Result Retcode: ",m_trade.ResultRetcode(),
                     ", description of result: ",m_trade.ResultRetcodeDescription());
              }
           }
         else
           {
            Print("Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
                  ", description of result: ",m_trade.ResultRetcodeDescription());
           }
        }
//---
  }
//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+

void OnTradeTransaction(const MqlTradeTransaction &trans, 
                        const MqlTradeRequest &request, 
                        const MqlTradeResult &result) 
  { 
  
   static int counter=0;   // contador de chamadas da OnTradeTransaction() 
   static uint lasttime=0; // hora da última chamada da OnTradeTransaction() 
   uint time=GetTickCount(); 
//--- se a última operação tiver sido realizada há mais de 1 segundo, 
   if(time-lasttime>1000) 
     { 
      counter=0; // significa que se trata de uma nova operação de negociação e, portanto, podemos redefinir o contador 
      if(IS_DEBUG_MODE) 
         Print(" Nova operação de negociação"); 
     } 
   lasttime=time; 
   counter++; 
   Print(counter,". ",__FUNCTION__); 
//--- resultado da execução do pedido de negociação 
   ulong            lastOrderID   =trans.order; 
   ENUM_ORDER_TYPE  lastOrderType =trans.order_type; 
   ENUM_ORDER_STATE lastOrderState=trans.order_state; 
   string trans_symbol=trans.symbol; 
   ENUM_TRADE_TRANSACTION_TYPE  trans_type=trans.type; 
   

   if(HistoryDealSelect(trans.deal) == true){
     ENUM_DEAL_ENTRY deal_entry=(ENUM_DEAL_ENTRY) HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
     ENUM_DEAL_REASON deal_reason=(ENUM_DEAL_REASON) HistoryDealGetInteger(trans.deal,DEAL_REASON);
     PrintFormat("deal entry type=%s trans type=%s trans deal type=%s order-ticket=%d deal-ticket=%d deal-reason=%s",EnumToString(deal_entry),EnumToString(trans.type),EnumToString(trans.deal_type),trans.order,trans.deal,EnumToString(deal_reason));
   }
  
   
   switch(trans.type) 
     { 
      case  TRADE_TRANSACTION_POSITION:   // alteração da posição 
        { 
         ulong pos_ID=trans.position; 
         PrintFormat("MqlTradeTransaction: Position  #%d %s modified: SL=%.5f TP=%.5f", 
                     pos_ID,trans_symbol,trans.price_sl,trans.price_tp); 
        } 
      break; 
      case TRADE_TRANSACTION_REQUEST:     // envio do pedido de negociação 
         PrintFormat("MqlTradeTransaction: TRADE_TRANSACTION_REQUEST"); 
         break; 
      case TRADE_TRANSACTION_DEAL_ADD:    // adição da transação 
        { 
         ulong           lastDealID   =trans.deal; 
         ENUM_DEAL_TYPE  lastDealType =trans.deal_type; 
       
       
        ENUM_DEAL_ENTRY deal_entry=(ENUM_DEAL_ENTRY) HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
         double        lastDealVolume=trans.volume; 
         //--- identificador da transação no sistema externo - bilhete atribuído pela bolsa 
         string Exchange_ticket=""; 
         if(HistoryDealSelect(lastDealID)) 
            Exchange_ticket=HistoryDealGetString(lastDealID,DEAL_EXTERNAL_ID); 
         if(Exchange_ticket!="") 
            Exchange_ticket=StringFormat("(Exchange deal=%s)",Exchange_ticket); 
  
         PrintFormat("MqlTradeTransaction: %s deal #%d %s %s %.2f lot   %s",EnumToString(trans_type), 
                     lastDealID,EnumToString(lastDealType),trans_symbol,lastDealVolume,Exchange_ticket); 
                     
         // Caso estiver saindo da posição
         if ( deal_entry==DEAL_ENTRY_OUT) {
          
            datetime dataOperacao = TimeCurrent();
            string simbolo = StringSubstr(trans_symbol,0,3); 
            
            if ( StringCompare(simbolo,"WIN",false)==0) { 
               HistoricoDiario();
               
               double profit = HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
               if (profit != 0) {
                   eventoResultadoPosicao(trans_symbol,lastDealVolume,EnumToString(trans_type),trans.deal,profit,result.retcode,trans.position , EnumToString(trans.deal_type) );
                  PrintFormat("Profit Resultado Simbolo: %s - Volume: %s - Tipo: %s - Ticket: %s - Profit: %s - Status: %s - Posicao: %s",
                      trans_symbol,DoubleToString(lastDealVolume,0),EnumToString(trans_type),DoubleToString(trans.deal,0), DoubleToString(profit,0), IntegerToString(result.retcode), DoubleToString(trans.position));
               } 
               
               sequenciaPosicao(trans_symbol,profit,trans.position,dataOperacao);
               HistoricoMensal();
            }
            
             
         }
        } 
      break; 
      case TRADE_TRANSACTION_HISTORY_ADD: // adição da ordem ao histórico 
        { 
         //--- identificador da transação no sistema externo - bilhete atribuído pela bolsa 
         string Exchange_ticket=""; 
         if(lastOrderState==ORDER_STATE_FILLED) 
           { 
            if(HistoryOrderSelect(lastOrderID)) 
               Exchange_ticket=HistoryOrderGetString(lastOrderID,ORDER_EXTERNAL_ID); 
            if(Exchange_ticket!="") 
               Exchange_ticket=StringFormat("(Exchange ticket=%s)",Exchange_ticket); 
           } 
         PrintFormat("MqlTradeTransaction: %s order #%d %s %s %s   %s",EnumToString(trans_type), 
                     lastOrderID,EnumToString(lastOrderType),trans_symbol,EnumToString(lastOrderState),Exchange_ticket); 
        } 
      break; 
      default: // outras transações   
        { 
         //--- identificador da ordem no sistema externo - bilhete atribuído pela Bolsa de Valores de Moscou 
         string Exchange_ticket=""; 
         if(lastOrderState==ORDER_STATE_PLACED) 
           { 
            if(OrderSelect(lastOrderID)) 
               Exchange_ticket=OrderGetString(ORDER_EXTERNAL_ID); 
            if(Exchange_ticket!="") 
               Exchange_ticket=StringFormat("Exchange ticket=%s",Exchange_ticket); 
           } 
         PrintFormat("MqlTradeTransaction(Default, orderPlaced): %s order #%d %s %s   %s",EnumToString(trans_type), 
                     lastOrderID,EnumToString(lastOrderType),EnumToString(lastOrderState),Exchange_ticket); 
        } 
      break; 
     } 
//--- bilhete da ordem     
   ulong orderID_result=result.order; 
   string retcode_result=GetRetcodeID(result.retcode); 
   Print("Retorno da transacao",result.retcode);
   if(orderID_result!=0) 
      LOG(LOG_LEVEL_INFO, StringFormat("Retorno da operação ordem %d - retorno=%s", orderID_result,retcode_result));
      
//---    
  } 
  
 string GetRetcodeID(int retcode) 
  { 
   switch(retcode) 
     { 
      case 10004: return("TRADE_RETCODE_REQUOTE");             break; 
      case 10006: return("TRADE_RETCODE_REJECT");              break; 
      case 10007: return("TRADE_RETCODE_CANCEL");              break; 
      case 10008: return("TRADE_RETCODE_PLACED");              break; 
      case 10009: return("TRADE_RETCODE_DONE");                break; 
      case 10010: return("TRADE_RETCODE_DONE_PARTIAL");        break; 
      case 10011: return("TRADE_RETCODE_ERROR");               break; 
      case 10012: return("TRADE_RETCODE_TIMEOUT");             break; 
      case 10013: return("TRADE_RETCODE_INVALID");             break; 
      case 10014: return("TRADE_RETCODE_INVALID_VOLUME");      break; 
      case 10015: return("TRADE_RETCODE_INVALID_PRICE");       break; 
      case 10016: return("TRADE_RETCODE_INVALID_STOPS");       break; 
      case 10017: return("TRADE_RETCODE_TRADE_DISABLED");      break; 
      case 10018: return("TRADE_RETCODE_MARKET_CLOSED");       break; 
      case 10019: return("TRADE_RETCODE_NO_MONEY");            break; 
      case 10020: return("TRADE_RETCODE_PRICE_CHANGED");       break; 
      case 10021: return("TRADE_RETCODE_PRICE_OFF");           break; 
      case 10022: return("TRADE_RETCODE_INVALID_EXPIRATION");  break; 
      case 10023: return("TRADE_RETCODE_ORDER_CHANGED");       break; 
      case 10024: return("TRADE_RETCODE_TOO_MANY_REQUESTS");   break; 
      case 10025: return("TRADE_RETCODE_NO_CHANGES");          break; 
      case 10026: return("TRADE_RETCODE_SERVER_DISABLES_AT");  break; 
      case 10027: return("TRADE_RETCODE_CLIENT_DISABLES_AT");  break; 
      case 10028: return("TRADE_RETCODE_LOCKED");              break; 
      case 10029: return("TRADE_RETCODE_FROZEN");              break; 
      case 10030: return("TRADE_RETCODE_INVALID_FILL");        break; 
      case 10031: return("TRADE_RETCODE_CONNECTION");          break; 
      case 10032: return("TRADE_RETCODE_ONLY_REAL");           break; 
      case 10033: return("TRADE_RETCODE_LIMIT_ORDERS");        break; 
      case 10034: return("TRADE_RETCODE_LIMIT_VOLUME");        break; 
      case 10035: return("TRADE_RETCODE_INVALID_ORDER");       break; 
      case 10036: return("TRADE_RETCODE_POSITION_CLOSED");     break; 
      default: 
         return("TRADE_RETCODE_UNKNOWN="+IntegerToString(retcode)); 
         break; 
     } 
  }

 
 
 
bool HorarioRoboteste()  {
   TimeToStruct(TimeCurrent(),horario_atual);
   
   if(horario_atual.hour >= horario_inicio.hour && horario_atual.hour <= horario_termino.hour) {
      // Hora atual igual a de início
      if(horario_atual.hour == horario_inicio.hour)
      // Se minuto atual maior ou igual ao de início => está no horário de entradas
         if(horario_atual.min >= horario_inicio.min)
            return true;
   // Do contrário não está no horário de entradas
   else
      return false;
   
   // Hora atual igual a de término
   if(horario_atual.hour == horario_termino.hour)
   // Se minuto atual menor ou igual ao de término => está no horário de entradas
      if(horario_atual.min <= horario_termino.min)
         return true;
   // Do contrário não está no horário de entradas
      else
         return false;
   
   // Hora atual maior que a de início e menor que a de término
   return true;
}

// Hora fora do horário de entradas
   return false;
}

bool HorarioFechamento()
     {
      TimeToStruct(TimeCurrent(),horario_atual);
      
     
     // Hora dentro do horário de fechamento
   if(horario_atual.hour >= horario_fechamento.hour)
   {
      // Hora atual igual a de fechamento
      if(horario_atual.hour == horario_fechamento.hour)
         // Se minuto atual maior ou igual ao de fechamento => está no horário de fechamento
         if(horario_atual.min >= horario_fechamento.min)
            return true;
         // Do contrário não está no horário de fechamento
         else
            return false;
      
      // Hora atual maior que a de fechamento
      return true;
   }
   
   // Hora fora do horário de fechamento
   return false;
}

void sequenciaPosicao(string simbolo, double profit, ulong posicao, datetime dataOperacao) {

   bool existe = false;
   bool resultado = false;
       
   if (profit > 0)
      resultado = true;
   else {
      resultado = false;
   }
   
  
   if (sequencias.Total()==0) {
      sequencias.Add(new Sequencia(simbolo,resultado,posicao,dataOperacao));
      return;
   }

   for(int i=0;i<sequencias.Total();i++) {
      if(sequencias.Total() >= 1) {
         Sequencia *sequencia = sequencias.At(i);
         
         
         PrintFormat("Sequencia posicao Anterior: %s - Posicao Atual: %s- simbolo: %s - Data: %s - resultado %s - Simbolo: %s", DoubleToString(sequencia._posicao),
         DoubleToString(posicao),simbolo,TimeToString(dataOperacao), DoubleToString(resultado), sequencia._simbolo);
         
          LOG(LOG_LEVEL_INFO,StringFormat("Sequencia posicao Anterior: %s - Posicao Atual: %s- simbolo: %s - Data: %s - resultado %s", DoubleToString(sequencia._posicao),
         DoubleToString(posicao),simbolo,TimeToString(dataOperacao), DoubleToString(resultado)));
         
         if (sequencia._posicao == posicao) {
              Print("Posicões são iguais");
              existe = true;
         }
      }
      
    }
    if (!existe)
        sequencias.Add(new Sequencia(simbolo,resultado,posicao,dataOperacao));
        
    sequencias.Sort();
    
    for(int i=0;i<sequencias.Total();i++) {
 
       Sequencia *sequencia = sequencias.At(i);
       Sequencia *sequencia2 = sequencias.At(i-1);
       Sequencia *sequencia3 = sequencias.At(i-2);
 
       if ( (sequencia!=NULL && sequencia2!=NULL)&&(sequencia._resultado && sequencia2._resultado)) {
         Print("Duas sequencuas positivas");
         trade_ativo = false;
         LOG(LOG_LEVEL_INFO, "Sequência de operações com lucro atingido");
       }
       
       if ( (sequencia!=NULL && sequencia2!=NULL && sequencia3!=NULL)&&  (!sequencia._resultado && !sequencia2._resultado && !sequencia3._resultado)) {
          Print("Tres sequencuas negativas");
          trade_ativo = false;
          LOG(LOG_LEVEL_INFO, "Sequência de operações com prejuizo atingido");
       }
       
    }
 
}

