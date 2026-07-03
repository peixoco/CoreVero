export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      acao_corretiva: {
        Row: {
          created_at: string
          descricao: string
          empresa_id: string
          id: string
          resposta_id: string
          verificacao_id: string
        }
        Insert: {
          created_at?: string
          descricao: string
          empresa_id: string
          id?: string
          resposta_id: string
          verificacao_id: string
        }
        Update: {
          created_at?: string
          descricao?: string
          empresa_id?: string
          id?: string
          resposta_id?: string
          verificacao_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "acao_corretiva_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "acao_corretiva_empresa_id_resposta_id_fkey"
            columns: ["empresa_id", "resposta_id"]
            isOneToOne: false
            referencedRelation: "checklist_resposta"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "acao_corretiva_empresa_id_verificacao_id_fkey"
            columns: ["empresa_id", "verificacao_id"]
            isOneToOne: false
            referencedRelation: "verificacao"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      autorizacao: {
        Row: {
          created_at: string
          criada_em: string
          empresa_id: string
          expira_em: string
          id: string
          loja_id: string
          trabalhador_id: string
          usada_em: string | null
        }
        Insert: {
          created_at?: string
          criada_em?: string
          empresa_id: string
          expira_em: string
          id?: string
          loja_id: string
          trabalhador_id: string
          usada_em?: string | null
        }
        Update: {
          created_at?: string
          criada_em?: string
          empresa_id?: string
          expira_em?: string
          id?: string
          loja_id?: string
          trabalhador_id?: string
          usada_em?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "autorizacao_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "autorizacao_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "autorizacao_empresa_id_trabalhador_id_fkey"
            columns: ["empresa_id", "trabalhador_id"]
            isOneToOne: false
            referencedRelation: "trabalhador"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      checklist_instancia: {
        Row: {
          created_at: string
          due_at: string | null
          empresa_id: string
          estado: string
          id: string
          loja_id: string
          template_id: string
          template_versao: number
          verificacao_id: string
        }
        Insert: {
          created_at?: string
          due_at?: string | null
          empresa_id: string
          estado?: string
          id?: string
          loja_id: string
          template_id: string
          template_versao: number
          verificacao_id: string
        }
        Update: {
          created_at?: string
          due_at?: string | null
          empresa_id?: string
          estado?: string
          id?: string
          loja_id?: string
          template_id?: string
          template_versao?: number
          verificacao_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "checklist_instancia_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "checklist_instancia_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "checklist_instancia_empresa_id_template_id_fkey"
            columns: ["empresa_id", "template_id"]
            isOneToOne: false
            referencedRelation: "checklist_template"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "checklist_instancia_empresa_id_verificacao_id_fkey"
            columns: ["empresa_id", "verificacao_id"]
            isOneToOne: false
            referencedRelation: "verificacao"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      checklist_item: {
        Row: {
          created_at: string
          empresa_id: string
          id: string
          limite_max: number | null
          limite_min: number | null
          ordem: number
          template_id: string
          texto: string
          tipo_resposta: string
          unidade: string | null
        }
        Insert: {
          created_at?: string
          empresa_id: string
          id?: string
          limite_max?: number | null
          limite_min?: number | null
          ordem?: number
          template_id: string
          texto: string
          tipo_resposta: string
          unidade?: string | null
        }
        Update: {
          created_at?: string
          empresa_id?: string
          id?: string
          limite_max?: number | null
          limite_min?: number | null
          ordem?: number
          template_id?: string
          texto?: string
          tipo_resposta?: string
          unidade?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "checklist_item_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "checklist_item_empresa_id_template_id_fkey"
            columns: ["empresa_id", "template_id"]
            isOneToOne: false
            referencedRelation: "checklist_template"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      checklist_resposta: {
        Row: {
          conforme: boolean | null
          created_at: string
          empresa_id: string
          id: string
          instancia_id: string
          item_id: string
          valor: string | null
        }
        Insert: {
          conforme?: boolean | null
          created_at?: string
          empresa_id: string
          id?: string
          instancia_id: string
          item_id: string
          valor?: string | null
        }
        Update: {
          conforme?: boolean | null
          created_at?: string
          empresa_id?: string
          id?: string
          instancia_id?: string
          item_id?: string
          valor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "checklist_resposta_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "checklist_resposta_empresa_id_instancia_id_fkey"
            columns: ["empresa_id", "instancia_id"]
            isOneToOne: false
            referencedRelation: "checklist_instancia"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "checklist_resposta_empresa_id_item_id_fkey"
            columns: ["empresa_id", "item_id"]
            isOneToOne: false
            referencedRelation: "checklist_item"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      checklist_template: {
        Row: {
          ativo: boolean
          created_at: string
          empresa_id: string
          frequencia: string
          id: string
          loja_id: string | null
          nome: string
          versao: number
        }
        Insert: {
          ativo?: boolean
          created_at?: string
          empresa_id: string
          frequencia: string
          id?: string
          loja_id?: string | null
          nome: string
          versao?: number
        }
        Update: {
          ativo?: boolean
          created_at?: string
          empresa_id?: string
          frequencia?: string
          id?: string
          loja_id?: string | null
          nome?: string
          versao?: number
        }
        Relationships: [
          {
            foreignKeyName: "checklist_template_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "checklist_template_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      checklist_template_loja: {
        Row: {
          created_at: string
          empresa_id: string
          id: string
          loja_id: string
          template_id: string
        }
        Insert: {
          created_at?: string
          empresa_id: string
          id?: string
          loja_id: string
          template_id: string
        }
        Update: {
          created_at?: string
          empresa_id?: string
          id?: string
          loja_id?: string
          template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "checklist_template_loja_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "checklist_template_loja_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "checklist_template_loja_empresa_id_template_id_fkey"
            columns: ["empresa_id", "template_id"]
            isOneToOne: false
            referencedRelation: "checklist_template"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      empresa: {
        Row: {
          colaboradores_licenciados: number
          created_at: string
          id: string
          lojas_licenciadas: number
          nome: string
          plano: string | null
          retencao_foto_dias: number
        }
        Insert: {
          colaboradores_licenciados?: number
          created_at?: string
          id?: string
          lojas_licenciadas?: number
          nome: string
          plano?: string | null
          retencao_foto_dias?: number
        }
        Update: {
          colaboradores_licenciados?: number
          created_at?: string
          id?: string
          lojas_licenciadas?: number
          nome?: string
          plano?: string | null
          retencao_foto_dias?: number
        }
        Relationships: []
      }
      kiosk: {
        Row: {
          ativo: boolean
          chave_hmac: string | null
          chave_registada_em: string | null
          created_at: string
          empresa_id: string
          id: string
          loja_id: string
          revogado_em: string | null
          revogado_por: string | null
        }
        Insert: {
          ativo?: boolean
          chave_hmac?: string | null
          chave_registada_em?: string | null
          created_at?: string
          empresa_id: string
          id: string
          loja_id: string
          revogado_em?: string | null
          revogado_por?: string | null
        }
        Update: {
          ativo?: boolean
          chave_hmac?: string | null
          chave_registada_em?: string | null
          created_at?: string
          empresa_id?: string
          id?: string
          loja_id?: string
          revogado_em?: string | null
          revogado_por?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "kiosk_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "kiosk_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      loja: {
        Row: {
          ativa: boolean
          created_at: string
          empresa_id: string
          id: string
          nome: string
        }
        Insert: {
          ativa?: boolean
          created_at?: string
          empresa_id: string
          id?: string
          nome: string
        }
        Update: {
          ativa?: boolean
          created_at?: string
          empresa_id?: string
          id?: string
          nome?: string
        }
        Relationships: [
          {
            foreignKeyName: "loja_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
        ]
      }
      notificacao: {
        Row: {
          canal: string
          created_at: string
          destinatario: string | null
          empresa_id: string
          estado: string
          id: string
          origem_id: string | null
          tentativas: number
        }
        Insert: {
          canal?: string
          created_at?: string
          destinatario?: string | null
          empresa_id: string
          estado?: string
          id?: string
          origem_id?: string | null
          tentativas?: number
        }
        Update: {
          canal?: string
          created_at?: string
          destinatario?: string | null
          empresa_id?: string
          estado?: string
          id?: string
          origem_id?: string | null
          tentativas?: number
        }
        Relationships: [
          {
            foreignKeyName: "notificacao_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
        ]
      }
      picagem: {
        Row: {
          anulada: boolean
          anulada_em: string | null
          anulada_por: string | null
          created_at: string
          empresa_id: string
          id: string
          motivo_anulacao: string | null
          tipo: string
          verificacao_id: string
        }
        Insert: {
          anulada?: boolean
          anulada_em?: string | null
          anulada_por?: string | null
          created_at?: string
          empresa_id: string
          id?: string
          motivo_anulacao?: string | null
          tipo: string
          verificacao_id: string
        }
        Update: {
          anulada?: boolean
          anulada_em?: string | null
          anulada_por?: string | null
          created_at?: string
          empresa_id?: string
          id?: string
          motivo_anulacao?: string | null
          tipo?: string
          verificacao_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "picagem_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "picagem_empresa_id_verificacao_id_fkey"
            columns: ["empresa_id", "verificacao_id"]
            isOneToOne: false
            referencedRelation: "verificacao"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      picagem_recusada: {
        Row: {
          chave_idempotencia: string
          codigo_pessoal: string | null
          criada_em: string
          empresa_id: string
          estado: string
          id: string
          kiosk_id: string
          loja_id: string
          momento_dispositivo: string
          motivo: string
          picagem_id: string | null
          resolvida_em: string | null
          resolvida_por: string | null
          tipo: string
          trabalhador_id: string | null
        }
        Insert: {
          chave_idempotencia: string
          codigo_pessoal?: string | null
          criada_em?: string
          empresa_id: string
          estado?: string
          id?: string
          kiosk_id: string
          loja_id: string
          momento_dispositivo: string
          motivo: string
          picagem_id?: string | null
          resolvida_em?: string | null
          resolvida_por?: string | null
          tipo: string
          trabalhador_id?: string | null
        }
        Update: {
          chave_idempotencia?: string
          codigo_pessoal?: string | null
          criada_em?: string
          empresa_id?: string
          estado?: string
          id?: string
          kiosk_id?: string
          loja_id?: string
          momento_dispositivo?: string
          motivo?: string
          picagem_id?: string | null
          resolvida_em?: string | null
          resolvida_por?: string | null
          tipo?: string
          trabalhador_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "picagem_recusada_empresa_fk"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "picagem_recusada_loja_fk"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      trabalhador: {
        Row: {
          area: string | null
          ativo: boolean
          codigo_pessoal: string
          created_at: string
          empresa_id: string
          id: string
          nome: string
          pin: string | null
        }
        Insert: {
          area?: string | null
          ativo?: boolean
          codigo_pessoal: string
          created_at?: string
          empresa_id: string
          id?: string
          nome: string
          pin?: string | null
        }
        Update: {
          area?: string | null
          ativo?: boolean
          codigo_pessoal?: string
          created_at?: string
          empresa_id?: string
          id?: string
          nome?: string
          pin?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "trabalhador_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
        ]
      }
      trabalhador_detalhe: {
        Row: {
          contrato_fim: string | null
          contrato_inicio: string | null
          created_at: string
          data_nascimento: string | null
          email: string | null
          empresa_id: string
          nome_completo: string | null
          posicao: string | null
          telefone: string | null
          trabalhador_id: string
        }
        Insert: {
          contrato_fim?: string | null
          contrato_inicio?: string | null
          created_at?: string
          data_nascimento?: string | null
          email?: string | null
          empresa_id: string
          nome_completo?: string | null
          posicao?: string | null
          telefone?: string | null
          trabalhador_id: string
        }
        Update: {
          contrato_fim?: string | null
          contrato_inicio?: string | null
          created_at?: string
          data_nascimento?: string | null
          email?: string | null
          empresa_id?: string
          nome_completo?: string | null
          posicao?: string | null
          telefone?: string | null
          trabalhador_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trabalhador_detalhe_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trabalhador_detalhe_empresa_id_trabalhador_id_fkey"
            columns: ["empresa_id", "trabalhador_id"]
            isOneToOne: false
            referencedRelation: "trabalhador"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      trabalhador_loja: {
        Row: {
          created_at: string
          empresa_id: string
          id: string
          loja_id: string
          trabalhador_id: string
        }
        Insert: {
          created_at?: string
          empresa_id: string
          id?: string
          loja_id: string
          trabalhador_id: string
        }
        Update: {
          created_at?: string
          empresa_id?: string
          id?: string
          loja_id?: string
          trabalhador_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trabalhador_loja_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trabalhador_loja_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "trabalhador_loja_empresa_id_trabalhador_id_fkey"
            columns: ["empresa_id", "trabalhador_id"]
            isOneToOne: false
            referencedRelation: "trabalhador"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      utilizador_app: {
        Row: {
          ambito: string
          created_at: string
          empresa_id: string
          id: string
          loja_id: string | null
        }
        Insert: {
          ambito: string
          created_at?: string
          empresa_id: string
          id: string
          loja_id?: string | null
        }
        Update: {
          ambito?: string
          created_at?: string
          empresa_id?: string
          id?: string
          loja_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "utilizador_app_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "utilizador_app_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      verificacao: {
        Row: {
          autorizacao_offline: boolean
          chave_idempotencia: string | null
          correcao_manual: boolean
          created_at: string
          criada_por: string | null
          empresa_id: string
          foto_url: string | null
          id: string
          loja_id: string
          momento_dispositivo: string
          momento_servidor: string
          trabalhador_id: string
        }
        Insert: {
          autorizacao_offline?: boolean
          chave_idempotencia?: string | null
          correcao_manual?: boolean
          created_at?: string
          criada_por?: string | null
          empresa_id: string
          foto_url?: string | null
          id?: string
          loja_id: string
          momento_dispositivo: string
          momento_servidor?: string
          trabalhador_id: string
        }
        Update: {
          autorizacao_offline?: boolean
          chave_idempotencia?: string | null
          correcao_manual?: boolean
          created_at?: string
          criada_por?: string | null
          empresa_id?: string
          foto_url?: string | null
          id?: string
          loja_id?: string
          momento_dispositivo?: string
          momento_servidor?: string
          trabalhador_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "verificacao_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "verificacao_empresa_id_loja_id_fkey"
            columns: ["empresa_id", "loja_id"]
            isOneToOne: false
            referencedRelation: "loja"
            referencedColumns: ["empresa_id", "id"]
          },
          {
            foreignKeyName: "verificacao_empresa_id_trabalhador_id_fkey"
            columns: ["empresa_id", "trabalhador_id"]
            isOneToOne: false
            referencedRelation: "trabalhador"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
    }
    Views: {
      vista_horas_dia: {
        Row: {
          dia: string | null
          empresa_id: string | null
          horas_pausa: number | null
          horas_trabalho: number | null
          incompleto: boolean | null
          seg_pausa: number | null
          seg_trabalho: number | null
          todos_fechados: boolean | null
          trabalhador_id: string | null
          turnos: number | null
        }
        Relationships: [
          {
            foreignKeyName: "verificacao_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "verificacao_empresa_id_trabalhador_id_fkey"
            columns: ["empresa_id", "trabalhador_id"]
            isOneToOne: false
            referencedRelation: "trabalhador"
            referencedColumns: ["empresa_id", "id"]
          },
        ]
      }
      vista_picagem: {
        Row: {
          anulada: boolean | null
          codigo_pessoal: string | null
          correcao_manual: boolean | null
          empresa_id: string | null
          foto_url: string | null
          loja_id: string | null
          loja_nome: string | null
          momento_dispositivo: string | null
          momento_servidor: string | null
          motivo_anulacao: string | null
          picagem_id: string | null
          tipo: string | null
          trabalhador_id: string | null
          trabalhador_nome: string | null
          verificacao_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "picagem_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "empresa"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      aceitar_recusa: { Args: { p_recusa_id: string }; Returns: Json }
      anular_picagem: {
        Args: { p_motivo: string; p_picagem_id: string }
        Returns: undefined
      }
      aplicar_correcoes: { Args: { p_linhas: Json }; Returns: Json }
      aplicar_folha: {
        Args: { p_linhas: Json; p_simular?: boolean }
        Returns: Json
      }
      atualizar_colaborador: {
        Args: {
          p_area: string
          p_contrato_fim?: string
          p_contrato_inicio?: string
          p_data_nascimento?: string
          p_email?: string
          p_id: string
          p_nome: string
          p_nome_completo?: string
          p_posicao?: string
          p_telefone?: string
        }
        Returns: undefined
      }
      corrigir_picagem: {
        Args: {
          p_loja_id?: string
          p_momento: string
          p_motivo?: string
          p_tipo: string
          p_trabalhador_id: string
        }
        Returns: Json
      }
      corrigir_picagem_bloco: {
        Args: {
          p_datas: string[]
          p_loja_id?: string
          p_movimentos: Json
          p_simular?: boolean
          p_trabalhadores: string[]
        }
        Returns: Json
      }
      criar_colaborador: {
        Args: {
          p_area: string
          p_contrato_fim?: string
          p_contrato_inicio?: string
          p_data_nascimento?: string
          p_email?: string
          p_nome: string
          p_nome_completo?: string
          p_posicao?: string
          p_telefone?: string
        }
        Returns: {
          codigo_pessoal: string
          pin: string
          trabalhador_id: string
        }[]
      }
      descartar_recusa: { Args: { p_recusa_id: string }; Returns: undefined }
      empresa_atual: { Args: never; Returns: string }
      gerar_novo_pin: { Args: { p_trabalhador_id: string }; Returns: string }
      iniciar_picagem: {
        Args: { p_codigo_pessoal: string; p_pin: string }
        Returns: Json
      }
      is_admin: { Args: never; Returns: boolean }
      is_kiosk: { Args: never; Returns: boolean }
      jwt_app_meta: { Args: never; Returns: Json }
      kiosk_ativo: { Args: never; Returns: boolean }
      limpar_autorizacoes: { Args: never; Returns: number }
      loja_atual: { Args: never; Returns: string }
      obter_cache_pins: {
        Args: never
        Returns: {
          codigo_pessoal: string
          nome: string
          pin_hmac: string
          trabalhador_id: string
          ultimo_momento: string
          ultimo_tipo: string
        }[]
      }
      purgar_fotos_expiradas: { Args: never; Returns: number }
      reativar_kiosk: { Args: { p_kiosk_id: string }; Returns: undefined }
      registar_chave_kiosk: {
        Args: { p_chave_hex: string }
        Returns: undefined
      }
      registar_picagem: {
        Args: {
          p_autorizacao_id: string
          p_chave_idempotencia: string
          p_momento_dispositivo: string
          p_tipo: string
        }
        Returns: Json
      }
      registar_picagem_offline: {
        Args: {
          p_chave_idempotencia: string
          p_momento_dispositivo: string
          p_tipo: string
          p_trabalhador_id: string
        }
        Returns: Json
      }
      reportar_picagem_recusada: {
        Args: {
          p_chave_idempotencia: string
          p_codigo_pessoal: string
          p_momento_dispositivo: string
          p_motivo: string
          p_tipo: string
          p_trabalhador_id: string
        }
        Returns: undefined
      }
      revogar_kiosk: { Args: { p_kiosk_id: string }; Returns: undefined }
      sequencia_valida: {
        Args: {
          p_empresa: string
          p_momento: string
          p_tipo: string
          p_trabalhador: string
        }
        Returns: boolean
      }
      terminar_sessao_kiosk: {
        Args: { p_kiosk_id: string }
        Returns: undefined
      }
      verificacao_do_trabalhador: {
        Args: { p_trabalhador_id: string; p_verificacao_id: string }
        Returns: boolean
      }
      verificacao_pertence_kiosk: {
        Args: { p_verificacao_id: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
